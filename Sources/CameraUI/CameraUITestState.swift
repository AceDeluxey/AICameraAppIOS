#if DEBUG
    struct CameraUITestState {
        let isEnabled: Bool
        let cameraState: CameraSessionController.State?

        init(processArguments: [String]) {
            isEnabled = processArguments.contains("--ui-testing")
            if processArguments.contains("--camera-unauthorized") {
                cameraState = .unauthorized
            } else if isEnabled {
                cameraState = .running
            } else {
                cameraState = nil
            }
        }
    }
#endif
