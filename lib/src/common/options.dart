// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'expression.dart';
import 'params.dart';

GlobalOptions _globalOptions = const GlobalOptions();

/// Sets default options applied to all subsequently declared functions.
///
/// Per-function options override these defaults. For callable functions,
/// [GlobalOptions.enforceAppCheck] is also used at runtime unless overridden by
/// the callable's own options.
void setGlobalOptions(GlobalOptions options) {
  _globalOptions = options;
}

/// Gets the current default options.
///
/// This is used internally by trigger registration.
GlobalOptions getGlobalOptions() => _globalOptions;

/// Global options that apply to all function types.
///
/// Matches the GlobalOptions interface from the Node.js SDK.
class GlobalOptions {
  const GlobalOptions({
    this.concurrency,
    this.cpu,
    this.enforceAppCheck,
    this.ingressSettings,
    this.invoker,
    this.labels,
    this.minInstances,
    this.maxInstances,
    this.memory,
    this.omit,
    this.preserveExternalChanges,
    this.region,
    this.secrets,
    this.serviceAccount,
    this.timeoutSeconds,
    this.vpcConnector,
    this.vpcConnectorEgressSettings,
  });

  /// Maximum number of concurrent requests per instance.
  final Concurrency? concurrency;

  /// Amount of CPU to allocate to the function.
  final Cpu? cpu;

  /// Whether to enforce Firebase App Check for callable functions.
  final EnforceAppCheck? enforceAppCheck;

  /// Ingress settings controlling who can call the function.
  final Ingress? ingressSettings;

  /// Who can invoke the function (public or specific service accounts).
  final Invoker? invoker;

  /// Labels to apply to the function for organization.
  final Map<String, String>? labels;

  /// Minimum number of instances to keep warm.
  final Instances? minInstances;

  /// Maximum number of instances.
  final Instances? maxInstances;

  /// Amount of memory to allocate to the function.
  final Memory? memory;

  /// Whether to omit this function from deployment.
  final Omit? omit;

  /// Whether to preserve changes made outside of deployment.
  final PreserveExternalChanges? preserveExternalChanges;

  /// Region(s) where the function should run.
  final Region? region;

  /// List of secrets this function needs access to.
  ///
  /// Only secrets listed here will be available via `.value()` at runtime.
  /// Supports both [SecretParam] (from [defineSecret]) and [JsonSecretParam]
  /// (from [defineJsonSecret]).
  ///
  /// Example:
  /// ```dart
  /// final apiKey = defineSecret('API_KEY');
  /// final apiConfig = defineJsonSecret<Map<String, dynamic>>('API_CONFIG');
  ///
  /// firebase.https.onRequest(
  ///   name: 'secure',
  ///   options: HttpsOptions(secrets: [apiKey, apiConfig]),
  ///   (request) async {
  ///     final key = apiKey.value();
  ///     final config = apiConfig.value();
  ///     return Response.ok('Configured');
  ///   },
  /// );
  /// ```
  final List<Object>? secrets; // SecretParam | JsonSecretParam

  /// Service account to run the function as.
  final ServiceAccount? serviceAccount;

  /// Timeout in seconds for the function.
  final TimeoutSeconds? timeoutSeconds;

  /// VPC connector for the function.
  final VpcConnector? vpcConnector;

  /// VPC egress settings.
  final VpcConnectorEgressSettings? vpcConnectorEgressSettings;
}

/// Base class for all option types.
///
/// Options can be:
/// - Literal values
/// - Expressions (for conditional logic)
/// - Parameters (user-configurable at deploy time)
sealed class Option<T extends Object> extends Expression<T> {
  const factory Option(T value) = OptionLiteral<T>;
  const factory Option.expression(Expression<T> expression) =
      OptionExpression<T>;
  const factory Option.param(Param<T> param) = OptionParam<T>;

  const Option._();

  @override
  T runtimeValue() {
    throw UnimplementedError('Subclass must implement runtimeValue()');
  }
}

/// Deploy-time options that can also be reset to default.
sealed class DeployOption<T extends Object> extends Option<T> {
  const factory DeployOption(T value) = OptionLiteral<T>;
  const factory DeployOption.expression(Expression<T> expression) =
      OptionExpression<T>;
  const factory DeployOption.param(Param<T> param) = OptionParam<T>;
  const factory DeployOption.reset() = OptionReset<T>;

  const DeployOption._() : super._();
}

/// Option value that resets to platform default.
final class OptionReset<T extends Object> extends DeployOption<T> {
  const OptionReset() : super._();

  @override
  T runtimeValue() {
    throw UnsupportedError('Reset option has no runtime value');
  }
}

/// Option with a literal value.
final class OptionLiteral<T extends Object> extends DeployOption<T> {
  const OptionLiteral(this.literal) : super._();
  final T literal;

  @override
  T runtimeValue() => literal;
}

/// Option with an expression value.
final class OptionExpression<T extends Object> extends DeployOption<T> {
  const OptionExpression(this.expression) : super._();
  final Expression<T> expression;

  @override
  T runtimeValue() => expression.runtimeValue();
}

/// Option with a parameter value.
final class OptionParam<T extends Object> extends DeployOption<T> {
  const OptionParam(this.param) : super._();
  final Param<T> param;

  @override
  T runtimeValue() => param.runtimeValue();
}

// Type aliases for common options (matches Node.js SDK)

typedef Concurrency = DeployOption<int>;
typedef EnforceAppCheck = Option<bool>;
typedef Ingress = DeployOption<IngressSetting>;
typedef Instances = DeployOption<int>;
typedef Omit = Option<bool>;
typedef PreserveExternalChanges = Option<bool>;
typedef Region = DeployOption<SupportedRegion>;
typedef ServiceAccount = DeployOption<String>;
typedef TimeoutSeconds = DeployOption<int>;
typedef VpcConnector = DeployOption<String>;
typedef VpcConnectorEgressSettings = DeployOption<VpcEgressSetting>;

/// Memory option with special handling for predefined values.
sealed class Memory extends DeployOption<int> {
  const factory Memory(MemoryOption value) = _MemoryLiteral;
  factory Memory.fromOption(MemoryOption value) =>
      _MemoryLiteral.fromOption(value);
  factory Memory.fromInt(int value) => _MemoryLiteral.fromInt(value);
  const factory Memory.expression(Expression<int> expression) =
      _MemoryExpression;
  const factory Memory.param(Param<int> param) = _MemoryParam;
  const factory Memory.reset() = _MemoryReset;

  // ignore: unused_element
  const Memory._() : super._();
}

final class _MemoryLiteral extends OptionLiteral<int> implements Memory {
  const _MemoryLiteral(MemoryOption value)
    : super(
        identical(value, MemoryOption.mb128)
            ? 128
            : identical(value, MemoryOption.mb256)
            ? 256
            : identical(value, MemoryOption.mb512)
            ? 512
            : identical(value, MemoryOption.gb1)
            ? 1024
            : identical(value, MemoryOption.gb2)
            ? 2048
            : identical(value, MemoryOption.gb4)
            ? 4096
            : identical(value, MemoryOption.gb8)
            ? 8192
            : identical(value, MemoryOption.gb16)
            ? 16384
            : 32768,
      );

  _MemoryLiteral.fromOption(MemoryOption value) : super(value.value);
  _MemoryLiteral.fromInt(super.value);
}

final class _MemoryExpression extends OptionExpression<int> implements Memory {
  const _MemoryExpression(super.expression);
}

final class _MemoryParam extends OptionParam<int> implements Memory {
  const _MemoryParam(super.param);
}

final class _MemoryReset extends OptionReset<int> implements Memory {
  const _MemoryReset();
}

/// Predefined memory options.
final class MemoryOption {
  const MemoryOption(this.value);

  final int value;

  static const mb128 = MemoryOption(128);
  static const mb256 = MemoryOption(256);
  static const mb512 = MemoryOption(512);
  static const gb1 = MemoryOption(1024);
  static const gb2 = MemoryOption(2048);
  static const gb4 = MemoryOption(4096);
  static const gb8 = MemoryOption(8192);
  static const gb16 = MemoryOption(16384);
  static const gb32 = MemoryOption(32768);
}

/// CPU option with special handling for GCF gen1.
sealed class Cpu extends DeployOption<double> {
  const factory Cpu(double value) = _CpuLiteral;
  const factory Cpu.expression(Expression<double> expression) = _CpuExpression;
  const factory Cpu.param(Param<double> param) = _CpuParam;
  const factory Cpu.reset() = _CpuReset;
  const factory Cpu.gcfGen1() = _CpuGcfGen1;

  // ignore: unused_element
  const Cpu._() : super._();
}

final class _CpuLiteral extends OptionLiteral<double> implements Cpu {
  const _CpuLiteral(super.literal);
}

final class _CpuExpression extends OptionExpression<double> implements Cpu {
  const _CpuExpression(super.expression);
}

final class _CpuParam extends OptionParam<double> implements Cpu {
  const _CpuParam(super.param);
}

final class _CpuReset extends OptionReset<double> implements Cpu {
  const _CpuReset();
}

final class _CpuGcfGen1 extends DeployOption<double> implements Cpu {
  const _CpuGcfGen1() : super._();

  @override
  double runtimeValue() => 0.583; // GCF Gen1 default CPU
}

/// Invoker option with helpers for public/private access.
sealed class Invoker extends DeployOption<List<String>> {
  const factory Invoker(List<String> value) = _InvokerLiteral;
  const factory Invoker.expression(Expression<List<String>> expression) =
      _InvokerExpression;
  const factory Invoker.param(Param<List<String>> param) = _InvokerParam;
  const factory Invoker.reset() = _InvokerReset;
  const factory Invoker.public() = _InvokerPublic;
  const factory Invoker.private() = _InvokerPrivate;

  // ignore: unused_element
  const Invoker._() : super._();
}

final class _InvokerLiteral extends OptionLiteral<List<String>>
    implements Invoker {
  const _InvokerLiteral(super.literal);
}

final class _InvokerExpression extends OptionExpression<List<String>>
    implements Invoker {
  const _InvokerExpression(super.expression);
}

final class _InvokerParam extends OptionParam<List<String>> implements Invoker {
  const _InvokerParam(super.param);
}

final class _InvokerReset extends OptionReset<List<String>> implements Invoker {
  const _InvokerReset();
}

final class _InvokerPublic extends DeployOption<List<String>>
    implements Invoker {
  const _InvokerPublic() : super._();

  @override
  List<String> runtimeValue() => ['public'];
}

final class _InvokerPrivate extends DeployOption<List<String>>
    implements Invoker {
  const _InvokerPrivate() : super._();

  @override
  List<String> runtimeValue() => ['private'];
}

/// Ingress settings for controlling network access.
enum IngressSetting {
  allowAll('ALLOW_ALL'),
  allowInternalOnly('ALLOW_INTERNAL_ONLY'),
  allowInternalAndGclb('ALLOW_INTERNAL_AND_GCLB');

  const IngressSetting(this.value);
  final String value;
}

/// Supported Cloud Functions regions.
enum SupportedRegion {
  asiaEast1('asia-east1'),
  asiaEast2('asia-east2'),
  asiaNortheast1('asia-northeast1'),
  asiaNortheast2('asia-northeast2'),
  asiaNortheast3('asia-northeast3'),
  asiaSouth1('asia-south1'),
  asiaSoutheast1('asia-southeast1'),
  asiaSoutheast2('asia-southeast2'),
  australiaSoutheast1('australia-southeast1'),
  europeCentral2('europe-central2'),
  europeNorth1('europe-north1'),
  europeWest1('europe-west1'),
  europeWest2('europe-west2'),
  europeWest3('europe-west3'),
  europeWest4('europe-west4'),
  europeWest6('europe-west6'),
  northAmericaNortheast1('northamerica-northeast1'),
  southAmericaEast1('southamerica-east1'),
  usCentral1('us-central1'),
  usEast1('us-east1'),
  usEast4('us-east4'),
  usWest1('us-west1'),
  usWest2('us-west2'),
  usWest3('us-west3'),
  usWest4('us-west4');

  const SupportedRegion(this.value);
  final String value;
}

/// VPC egress settings.
enum VpcEgressSetting {
  privateRangesOnly('PRIVATE_RANGES_ONLY'),
  allTraffic('ALL_TRAFFIC');

  const VpcEgressSetting(this.value);
  final String value;
}
