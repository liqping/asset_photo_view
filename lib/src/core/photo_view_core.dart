import 'package:flutter/widgets.dart';
import '../../photo_view.dart'
    show
        PhotoViewScaleState,
        PhotoViewHeroAttributes,
        PhotoViewImageTapDownCallback,
        PhotoViewImageTapUpCallback,
        PhotoViewImageScaleEndCallback,
        ScaleStateCycle;
import '../../src/controller/photo_view_controller.dart';
import '../../src/controller/photo_view_controller_delegate.dart';
import '../../src/controller/photo_view_scalestate_controller.dart';
import '../../src/core/photo_view_gesture_detector.dart';
import '../../src/core/photo_view_hit_corners.dart';
import '../../src/utils/photo_view_utils.dart';

const _defaultDecoration = BoxDecoration(
  color: Color.fromRGBO(0, 0, 0, 1.0),
);

/// Internal widget in which controls all animations lifecycle, core responses
/// to user gestures, updates to  the controller state and mounts the entire PhotoView Layout
class PhotoViewCore extends StatefulWidget {
  const PhotoViewCore({
    Key? key,
    this.data,
    required this.enableScaleAndDoubleTap,
    required this.imageProvider,
    required this.backgroundDecoration,
    required this.gaplessPlayback,
    required this.heroAttributes,
    required this.enableRotation,
    required this.onTapUp,
    required this.onTapDown,
    required this.onScaleEnd,
    required this.gestureDetectorBehavior,
    required this.controller,
    required this.scaleBoundaries,
    required this.scaleStateCycle,
    required this.scaleStateController,
    required this.basePosition,
    required this.tightMode,
    required this.filterQuality,
    required this.disableGestures,
    required this.enablePanAlways,
  })  : customChild = null,
        super(key: key);

  const PhotoViewCore.customChild({
    Key? key,
    this.data,
    required this.enableScaleAndDoubleTap,
    required this.customChild,
    required this.backgroundDecoration,
    this.heroAttributes,
    required this.enableRotation,
    this.onTapUp,
    this.onTapDown,
    this.onScaleEnd,
    this.gestureDetectorBehavior,
    required this.controller,
    required this.scaleBoundaries,
    required this.scaleStateCycle,
    required this.scaleStateController,
    required this.basePosition,
    required this.tightMode,
    required this.filterQuality,
    required this.disableGestures,
    required this.enablePanAlways,
  })  : imageProvider = null,
        gaplessPlayback = false,
        super(key: key);

  final ValueNotifier? data;

  final bool enableScaleAndDoubleTap;  //音视频需要屏蔽

  final Decoration? backgroundDecoration;
  final ImageProvider? imageProvider;
  final bool? gaplessPlayback;
  final PhotoViewHeroAttributes? heroAttributes;
  final bool enableRotation;
  final Widget? customChild;

  final PhotoViewControllerBase controller;
  final PhotoViewScaleStateController scaleStateController;
  final ScaleBoundaries scaleBoundaries;
  final ScaleStateCycle scaleStateCycle;
  final Alignment basePosition;

  final PhotoViewImageTapUpCallback? onTapUp;
  final PhotoViewImageTapDownCallback? onTapDown;
  final PhotoViewImageScaleEndCallback? onScaleEnd;

  final HitTestBehavior? gestureDetectorBehavior;
  final bool tightMode;
  final bool disableGestures;
  final bool enablePanAlways;

  final FilterQuality filterQuality;

  @override
  State<StatefulWidget> createState() {
    return PhotoViewCoreState();
  }

  bool get hasCustomChild => customChild != null;
}

class PhotoViewCoreState extends State<PhotoViewCore>
    with
        TickerProviderStateMixin,
        PhotoViewControllerDelegate,
        HitCornersDetector {
  Offset? _normalizedPosition;
  double? _scaleBefore;
  double? _rotationBefore;


  // late final AnimationController _scaleAnimationController =
  //     AnimationController(vsync: this)
  //       ..addListener(handleScaleAnimation)
  //       ..addStatusListener(onAnimationStatus);

  late AnimationController _scaleAnimationController;
  
  Animation<double>? _scaleAnimation;

  // late final AnimationController _positionAnimationController =
  //     AnimationController(vsync: this)..addListener(handlePositionAnimate);

  late AnimationController _positionAnimationController;
  
  Animation<Offset>? _positionAnimation;

  late AnimationController _rotationAnimationController;
  
  // late final AnimationController _rotationAnimationController =
  //     AnimationController(vsync: this)..addListener(handleRotationAnimation);
  Animation<double>? _rotationAnimation;

  PhotoViewHeroAttributes? get heroAttributes => widget.heroAttributes;

  late ScaleBoundaries cachedScaleBoundaries = widget.scaleBoundaries;

  void handleScaleAnimation() {
    scale = _scaleAnimation!.value;
  }

  void handlePositionAnimate() {
    controller.position = _positionAnimation!.value;
  }

  void handleRotationAnimation() {
    controller.rotation = _rotationAnimation!.value;
  }

  void onScaleStart(ScaleStartDetails details) {
    _rotationBefore = controller.rotation;
    _scaleBefore = scale;
    _normalizedPosition = details.focalPoint - controller.position;
    _scaleAnimationController.stop();
    _positionAnimationController.stop();
    _rotationAnimationController.stop();
  }

  void onScaleUpdate(ScaleUpdateDetails details) {

    final double newScale = _scaleBefore! * details.scale;
    final Offset delta = details.focalPoint - _normalizedPosition!;


    updateScaleStateFromNewScale(newScale);

    updateMultiple(
      scale: newScale,
      position: widget.enablePanAlways
          ? delta
          : clampPosition(position: delta * details.scale),
      rotation:
          widget.enableRotation ? _rotationBefore! + details.rotation : null,
      rotationFocusPoint: widget.enableRotation ? details.focalPoint : null,
    );
  }

  void onScaleEnd(ScaleEndDetails details) {
    final double scale0 = scale;
    final Offset position0 = controller.position;
    final double maxScale = scaleBoundaries.maxScale;
    final double minScale = scaleBoundaries.minScale;

    widget.onScaleEnd?.call(context, details, controller.value);

    //animate back to maxScale if gesture exceeded the maxScale specified
    if (scale0 > maxScale) {
      final double scaleComebackRatio = maxScale / scale0;
      animateScale(scale0, maxScale);
      final Offset clampedPosition = clampPosition(
        position: position0 * scaleComebackRatio,
        scale: maxScale,
      );
      animatePosition(position0, clampedPosition);
      return;
    }

    //animate back to minScale if gesture fell smaller than the minScale specified
    if (scale0 < minScale) {
      final double scaleComebackRatio = minScale / scale0;
      animateScale(scale0, minScale);
      animatePosition(
        position0,
        clampPosition(
          position: position0 * scaleComebackRatio,
          scale: minScale,
        ),
      );
      return;
    }
    // get magnitude from gesture velocity
    final double magnitude = details.velocity.pixelsPerSecond.distance;

    // animate velocity only if there is no scale change and a significant magnitude
    if (_scaleBefore! / scale0 == 1.0 && magnitude >= 400.0) {
      final Offset direction = details.velocity.pixelsPerSecond / magnitude;
      animatePosition(
        position0,
        clampPosition(position: position0 + direction * 100.0),
      );
    }
  }

  // void onDoubleTap() {
  //   nextScaleState();
  // }

  void animateScale(double from, double to) {
    _scaleAnimation = Tween<double>(
      begin: from,
      end: to,
    ).animate(_scaleAnimationController);
    _scaleAnimationController
      ..value = 0.0
      ..fling(velocity: 0.4);
  }

  void animatePosition(Offset from, Offset to) {
    _positionAnimation = Tween<Offset>(begin: from, end: to)
        .animate(_positionAnimationController);
    _positionAnimationController
      ..value = 0.0
      ..fling(velocity: 0.4);
  }

  void animateRotation(double from, double to) {
    _rotationAnimation = Tween<double>(begin: from, end: to)
        .animate(_rotationAnimationController);
    _rotationAnimationController
      ..value = 0.0
      ..fling(velocity: 0.4);
  }

  void onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      onAnimationStatusCompleted();
    }
  }

  void onPageIndexChanged()
  {
    setState(() {
      if(scale != 1.0)
      {
        scale = 1.0;
        scaleStateController.scaleState = PhotoViewScaleState.initial;
      }

    });
  }

  /// Check if scale is equal to initial after scale animation update
  void onAnimationStatusCompleted() {
    if (scaleStateController.scaleState != PhotoViewScaleState.initial &&
        scale == scaleBoundaries.initialScale) {
      scaleStateController.setInvisibly(PhotoViewScaleState.initial);
    }
    else if(scaleStateController.scaleState == PhotoViewScaleState.initial &&
        scale == scaleBoundaries.maxScale){
      scaleStateController.setInvisibly(PhotoViewScaleState.zoomedOut);
    }
  }
  
  
  @override
  void initState() {
    super.initState();

    _scaleAnimationController =
    AnimationController(vsync: this)
      ..addListener(handleScaleAnimation)
      ..addStatusListener(onAnimationStatus);

    _positionAnimationController =
    AnimationController(vsync: this)..addListener(handlePositionAnimate);

    _rotationAnimationController =
    AnimationController(vsync: this)..addListener(handleRotationAnimation);
    
    initDelegate();
    addAnimateOnScaleStateUpdate(animateOnScaleStateUpdate);

    cachedScaleBoundaries = widget.scaleBoundaries;

    _scaleAnimationController = AnimationController(vsync: this)
      ..addListener(handleScaleAnimation)
      ..addStatusListener(onAnimationStatus);
    _positionAnimationController = AnimationController(vsync: this)
      ..addListener(handlePositionAnimate);

    widget.data?.addListener(onPageIndexChanged);

  }

  void animateOnScaleStateUpdate(double prevScale, double nextScale) {
    animateScale(prevScale, nextScale);
    animatePosition(controller.position, Offset.zero);
    animateRotation(controller.rotation, 0.0);
  }



  @override
  void dispose() {
    widget.data?.removeListener(onPageIndexChanged);
    _scaleAnimationController.removeStatusListener(onAnimationStatus);
    _scaleAnimationController.dispose();
    _positionAnimationController.dispose();
    _rotationAnimationController.dispose();
    super.dispose();
  }

  void onTapUp(TapUpDetails details) {
    widget.onTapUp?.call(context, details, controller.value);
  }

  void onTapDown(TapDownDetails details) {
    widget.onTapDown?.call(context, details, controller.value);
  }

  @override
  Widget build(BuildContext context) {
    // Check if we need a recalc on the scale
    if (widget.scaleBoundaries != cachedScaleBoundaries) {
      markNeedsScaleRecalc = true;
      cachedScaleBoundaries = widget.scaleBoundaries;
    }

    return StreamBuilder(
        stream: controller.outputStateStream,
        initialData: controller.prevValue,
        builder: (
          BuildContext context,
          AsyncSnapshot<PhotoViewControllerValue> snapshot,
        ) {
          if (snapshot.hasData) {
            final PhotoViewControllerValue value = snapshot.data!;
            final useImageScale = widget.filterQuality != FilterQuality.none;

            final computedScale = useImageScale ? 1.0 : scale;

            final matrix = Matrix4.identity()
              ..translate(value.position.dx, value.position.dy)
              ..scale(computedScale)
              ..rotateZ(value.rotation);

            final Widget customChildLayout = CustomSingleChildLayout(
              delegate: _CenterWithOriginalSizeDelegate(
                scaleBoundaries.childSize,
                basePosition,
                useImageScale,
              ),
              child: _buildHero(),
            );

            final child = Container(
              constraints: widget.tightMode
                  ? BoxConstraints.tight(scaleBoundaries.childSize * scale)
                  : null,
              decoration: widget.backgroundDecoration ?? _defaultDecoration,
              child: Center(
                child: Transform(
                  transform: matrix,
                  alignment: basePosition,
                  child: customChildLayout,
                ),
              ),
            );

            if (widget.disableGestures) {
              return child;
            }

            return PhotoViewGestureDetector(
              onDoubleTap: (){
                if (scaleStateController.scaleState == PhotoViewScaleState.initial){
                  final double scale0 = scale;
                  final Offset position0 = controller.position;
                  final double maxScale = scaleBoundaries.maxScale;
                  final double scaleComebackRatio = maxScale / scale0;
                  animateScale(scale0, maxScale);
                  final Offset clampedPosition = clampPosition(
                    position: position0 * scaleComebackRatio,
                    scale: maxScale,
                  );
                  animatePosition(position0, clampedPosition);
                  // scaleStateController.scaleState = scaleStateCycle(scaleState);
                  return;
                }
                nextScaleState();

              },
              onScaleStart: onScaleStart,
              onScaleUpdate: onScaleUpdate,
              onScaleEnd: onScaleEnd,
              hitDetector: this,
              onTapUp: widget.onTapUp != null
                  ? (details) => widget.onTapUp!(context, details, value)
                  : null,
              onTapDown: widget.onTapDown != null
                  ? (details) => widget.onTapDown!(context, details, value)
                  : null,
              enableScaleAndDoubleTap: widget.enableScaleAndDoubleTap,
              child: child,
            );
          } else {
            return Container();
          }
        });
  }

  Widget _buildHero() {
    return heroAttributes != null
        ? Hero(
            tag: heroAttributes!.tag,
            createRectTween: heroAttributes!.createRectTween,
            flightShuttleBuilder: heroAttributes!.flightShuttleBuilder,
            placeholderBuilder: heroAttributes!.placeholderBuilder,
            transitionOnUserGestures: heroAttributes!.transitionOnUserGestures,
            child: _buildChild(),
          )
        : _buildChild();
  }

  Widget _buildChild() {
    return widget.hasCustomChild
        ? widget.customChild!
        : Image(
            image: widget.imageProvider!,
            gaplessPlayback: widget.gaplessPlayback ?? false,
            filterQuality: widget.filterQuality,
            width: scaleBoundaries.childSize.width * scale,
            fit: BoxFit.contain,
          );
  }
}

class _CenterWithOriginalSizeDelegate extends SingleChildLayoutDelegate {
  const _CenterWithOriginalSizeDelegate(
    this.subjectSize,
    this.basePosition,
    this.useImageScale,
  );

  final Size subjectSize;
  final Alignment basePosition;
  final bool useImageScale;

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final childWidth = useImageScale ? childSize.width : subjectSize.width;
    final childHeight = useImageScale ? childSize.height : subjectSize.height;

    final halfWidth = (size.width - childWidth) / 2;
    final halfHeight = (size.height - childHeight) / 2;

    final double offsetX = halfWidth * (basePosition.x + 1);
    final double offsetY = halfHeight * (basePosition.y + 1);
    return Offset(offsetX, offsetY);
  }

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return useImageScale
        ? const BoxConstraints()
        : BoxConstraints.tight(subjectSize);
  }

  @override
  bool shouldRelayout(_CenterWithOriginalSizeDelegate oldDelegate) {
    return oldDelegate != this;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _CenterWithOriginalSizeDelegate &&
          runtimeType == other.runtimeType &&
          subjectSize == other.subjectSize &&
          basePosition == other.basePosition &&
          useImageScale == other.useImageScale;

  @override
  int get hashCode =>
      subjectSize.hashCode ^ basePosition.hashCode ^ useImageScale.hashCode;
}
