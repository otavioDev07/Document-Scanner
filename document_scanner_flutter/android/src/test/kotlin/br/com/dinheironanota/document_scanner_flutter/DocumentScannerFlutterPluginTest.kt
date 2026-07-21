package br.com.dinheironanota.document_scanner_flutter

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.mockito.Mockito
import kotlin.test.Test

internal class DocumentScannerFlutterPluginTest {
    @Test
    fun getNativeStatusReportsStaticAndCameraCapabilities() {
        val plugin = DocumentScannerFlutterPlugin()
        val result: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(MethodCall("getNativeStatus", null), result)

        Mockito.verify(result).success(
            mapOf(
                "platform" to "android",
                "pluginVersion" to "0.2.0",
                "opencvVersion" to "4.12.0",
                "detectorAvailable" to true,
                "staticImageSupported" to true,
                "cameraPreviewSupported" to true,
            ),
        )
    }
}
