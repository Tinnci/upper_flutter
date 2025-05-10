import 'package:flutter/material.dart';

@immutable
class CustomSuccessColors extends ThemeExtension<CustomSuccessColors> {
  const CustomSuccessColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
  });

  final Color? success;
  final Color? onSuccess;
  final Color? successContainer;
  final Color? onSuccessContainer;

  @override
  CustomSuccessColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
  }) {
    return CustomSuccessColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
    );
  }

  @override
  CustomSuccessColors lerp(ThemeExtension<CustomSuccessColors>? other, double t) {
    if (other is! CustomSuccessColors) {
      return this;
    }
    return CustomSuccessColors(
      success: Color.lerp(success, other.success, t),
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t),
      successContainer: Color.lerp(successContainer, other.successContainer, t),
      onSuccessContainer: Color.lerp(onSuccessContainer, other.onSuccessContainer, t),
    );
  }

  // 可选: 添加一个静态辅助方法，方便在 Widget 中获取
  static CustomSuccessColors? of(BuildContext context) {
    return Theme.of(context).extension<CustomSuccessColors>();
  }
}
