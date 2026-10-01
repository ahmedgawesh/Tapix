import '../../../core/services/lan/lan_models.dart';
import 'lan_branch_enrollment_service.dart';

class LanBranchEnrollmentGatewayImpl implements LanBranchEnrollmentGateway {
  const LanBranchEnrollmentGatewayImpl(this._service);

  final LanBranchEnrollmentService _service;

  @override
  Future<LanBranchWriterBinding> activateWriter(
    LanBranchWriterActivationRequest request,
  ) => _service.activateRemoteWriter(
    enrollmentId: request.enrollmentId,
    secret: request.secret,
    remoteDatabaseId: request.remoteDatabaseId,
  );
}
