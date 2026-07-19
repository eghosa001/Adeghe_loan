import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/document_repository.dart';
import '../../data/models/document_entity.dart';

final documentRepositoryProvider = Provider<DocumentRepository>((ref) {
  return DocumentRepository(ref);
});

final customerDocumentsProvider =
    FutureProvider.family<List<CustomerDocument>, String>((ref, customerId) {
  return ref.watch(documentRepositoryProvider).forCustomer(customerId);
});
