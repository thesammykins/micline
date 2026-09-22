import AudioToolbox
import Testing
import MicLineUI

@Suite("Audio Unit parameter presentation")
struct AUParameterPresentationTests {
    @Test("Exponential negative range preserves the confirmed failing endpoint")
    func exponentialNegativeRangePreservesMinimum() {
        let flags = AudioUnitParameterOptions.flag_DisplayExponential
        #expect(AUParameterPresentation.parameterValue(
            at: 0, minimum: -20, maximum: -1, flags: flags
        ) == -20)

        let value = AUParameterPresentation.parameterValue(
            at: 0.37, minimum: -20, maximum: -1, flags: flags
        )
        #expect(abs(AUParameterPresentation.linearPosition(
            for: value, minimum: -20, maximum: -1, flags: flags
        ) - 0.37) < 0.000_001)
    }

    @Test("Every display scale preserves endpoints and round-trips interior positions")
    func displayScaleEndpointsAndRoundTrips() {
        let cases: [(AudioUnitParameterOptions, Double, Double)] = [
            ([], -3, 11),
            (.flag_DisplaySquareRoot, -9, 16),
            (.flag_DisplaySquared, -3, 7),
            (.flag_DisplayCubed, -2, 5),
            (.flag_DisplayCubeRoot, -8, 27),
            (.flag_DisplayExponential, -20, -1),
            (.flag_DisplayLogarithmic, 0.01, 20),
            (.flag_DisplayLogarithmic, 0.000_000_000_001, 0.01),
            (.flag_DisplayLogarithmic, -20, -1),
            (.flag_DisplayLogarithmic, -2, 5),
            (.flag_DisplayLogarithmic, 0, 5),
        ]

        for (flags, minimum, maximum) in cases {
            #expect(AUParameterPresentation.parameterValue(
                at: 0, minimum: minimum, maximum: maximum, flags: flags
            ) == minimum)
            #expect(AUParameterPresentation.parameterValue(
                at: 1, minimum: minimum, maximum: maximum, flags: flags
            ) == maximum)
            #expect(AUParameterPresentation.linearPosition(
                for: minimum, minimum: minimum, maximum: maximum, flags: flags
            ) == 0)
            #expect(AUParameterPresentation.linearPosition(
                for: maximum, minimum: minimum, maximum: maximum, flags: flags
            ) == 1)

            for position in [0.1, 0.37, 0.8] {
                let value = AUParameterPresentation.parameterValue(
                    at: position, minimum: minimum, maximum: maximum, flags: flags
                )
                let roundTrip = AUParameterPresentation.linearPosition(
                    for: value, minimum: minimum, maximum: maximum, flags: flags
                )
                #expect(abs(roundTrip - position) < 0.000_001)
            }
        }
    }

    @Test("Numeric fallback includes the Audio Unit supplied unit name")
    func numericFallbackIncludesUnitName() {
        let parameter = AUParameterTree.createParameter(
            withIdentifier: "threshold",
            name: "Threshold",
            address: 1,
            min: -60,
            max: 0,
            unit: .customUnit,
            unitName: "dB",
            flags: [.flag_IsReadable, .flag_IsWritable],
            valueStrings: nil,
            dependentParameters: nil
        )

        #expect(AUParameterPresentation.string(-12.5, parameter: parameter) == "-12.500 dB")
    }

    @Test("Audio Unit supplied value strings take precedence over numeric fallback")
    func suppliedValueStringsTakePrecedence() {
        let parameter = AUParameterTree.createParameter(
            withIdentifier: "mode",
            name: "Mode",
            address: 2,
            min: 0,
            max: 1,
            unit: .indexed,
            unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable, .flag_ValuesHaveStrings],
            valueStrings: ["Off", "On"],
            dependentParameters: nil
        )

        var value: AUValue = 1
        let supplied = parameter.string(fromValue: &value)
        #expect(AUParameterPresentation.string(value, parameter: parameter) == supplied)
        #expect(supplied != "+1.000")
    }
}
