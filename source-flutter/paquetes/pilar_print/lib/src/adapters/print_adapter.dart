import '../models/print_document.dart';
import '../models/print_job_result.dart';

abstract class PrintAdapter {
  Future<PrintJobResult> send(PrintDocument doc);
}
