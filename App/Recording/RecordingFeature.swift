// Recording mode exists only in the GymSpotSoloBeta target (specs/02 "Derleme
// yapılandırmaları", specs/09). In GymSpotSolo this file compiles to nothing and
// SoloRecording is not linked (AC-2.3).
#if RECORDING_MODE
import SoloRecording

#if RECORDING_MODE_RELEASE_FORBIDDEN
#error("GymSpotSoloBeta cannot be built with the Release configuration (specs/02). Archive GymSpotSolo for the App Store.")
#endif

enum RecordingFeature {
    /// Referenced at launch so the module is linked; replaced by the real entry
    /// point in T5.1.
    static func link() {
        _ = SoloRecording.moduleName
    }
}
#endif
