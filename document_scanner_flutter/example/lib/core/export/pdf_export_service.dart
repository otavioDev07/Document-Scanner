import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../features/documents/domain/scanned_document.dart';
import '../files/document_repository.dart';

final class PdfExportService {
  const PdfExportService(this._repository);

  final DocumentRepository _repository;

  Future<File> export(ScannedDocument document) async {
    if (document.pages.isEmpty) {
      throw StateError('Não é possível exportar um documento sem páginas.');
    }
    final pw.Document pdf = pw.Document(
      title: document.name,
      author: 'Document Scanner',
      creator: 'Document Scanner',
    );
    for (final ScannedPage page in document.pages) {
      final File file = await _repository.pageFile(document, page);
      final Uint8List bytes = await file.readAsBytes();
      final pw.MemoryImage image = pw.MemoryImage(bytes);
      final bool rotated = page.rotationQuarterTurns.isOdd;
      final bool landscape = rotated
          ? page.height > page.width
          : page.width > page.height;
      final PdfPageFormat format = landscape
          ? PdfPageFormat.a4.landscape
          : PdfPageFormat.a4;
      pdf.addPage(
        pw.Page(
          pageFormat: format,
          margin: const pw.EdgeInsets.all(12),
          build: (pw.Context context) {
            pw.Widget content = pw.Image(image, fit: pw.BoxFit.contain);
            if (page.rotationQuarterTurns != 0) {
              content = pw.Transform.rotate(
                angle: page.rotationQuarterTurns * math.pi / 2,
                child: content,
              );
            }
            return pw.Center(child: content);
          },
        ),
      );
    }

    final Directory exports = await _repository.exportsDirectory();
    final String safeName = document.name
        .replaceAll(RegExp(r'[^\p{L}\p{N}._-]+', unicode: true), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final File pending = File(
      path.join(exports.path, '${safeName}_${document.id}.pdf.pending'),
    );
    final File destination = File(
      path.join(exports.path, '${safeName}_${document.id}.pdf'),
    );
    await pending.writeAsBytes(await pdf.save(), flush: true);
    if (await destination.exists()) await destination.delete();
    return pending.rename(destination.path);
  }
}
