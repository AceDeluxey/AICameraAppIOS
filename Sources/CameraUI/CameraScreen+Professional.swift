import SwiftUI

extension CameraScreen {
    var captureModePicker: some View {
        VStack(spacing: 8) {
            if camera.captureMode == .video, !camera.availableVideoFormats.isEmpty {
                VideoFormatPicker(
                    options: camera.availableVideoFormats,
                    selectedOption: camera.selectedVideoFormat,
                    isDisabled: camera.videoRecordingStatus.isBusy,
                    selectOption: camera.selectVideoFormat
                )
            }
            HStack(spacing: 8) {
                CameraControlModePicker(
                    selectedMode: camera.controlMode,
                    supportsProfessionalMode: camera.professionalCapabilities?.supportsProfessionalMode == true,
                    isDisabled: camera.videoRecordingStatus.isBusy,
                    selectMode: camera.setControlMode
                )
                CaptureModePicker(
                    selectedMode: camera.captureMode,
                    isDisabled: camera.videoRecordingStatus.isBusy,
                    selectMode: camera.setCaptureMode
                )
            }
        }
    }

    @ViewBuilder
    var professionalControls: some View {
        if let capabilities = camera.professionalCapabilities,
           capabilities.exposureBiasRange != nil || camera.controlMode == .professional {
            CameraProfessionalControls(
                mode: camera.controlMode,
                capabilities: capabilities,
                settings: camera.professionalSettings,
                isDisabled: camera.videoRecordingStatus.isBusy,
                setControl: camera.setProfessionalControl
            )
        }
    }
}
