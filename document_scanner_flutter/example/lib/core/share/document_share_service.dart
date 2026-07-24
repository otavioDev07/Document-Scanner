import 'dart:io';
import 'dart:ui';

import 'package:share_plus/share_plus.dart';

final class DocumentShareService {
  const DocumentShareService();

  Future<ShareResult> sharePdf(
    File pdf,
    String documentName, {
    Rect? sharePositionOrigin,
  }) => SharePlus.instance.share(
    ShareParams(
      subject: documentName,
      title: documentName,
      text: 'Digitalizado com Document Scanner',
      files: <XFile>[XFile(pdf.path, mimeType: 'application/pdf')],
      sharePositionOrigin: sharePositionOrigin,
    ),
  );
}
