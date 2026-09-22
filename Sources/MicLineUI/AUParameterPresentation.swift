import AudioToolbox
import Foundation

public enum AUParameterPresentation {
    public static func string(_ value: AUValue, parameter: AUParameter) -> String {
        if parameter.flags.contains(.flag_ValuesHaveStrings) {
            var suppliedValue = value
            let supplied = parameter.string(fromValue: &suppliedValue)
            if !supplied.isEmpty { return supplied }
        }

        let numeric = String(format: "%+.3f", value)
        guard let unit = parameter.unitName, !unit.isEmpty else { return numeric }
        return "\(numeric) \(unit)"
    }

    public static func linearPosition(
        for value: Double,
        minimum: Double,
        maximum: Double,
        flags: AudioUnitParameterOptions
    ) -> Double {
        // AudioToolbox's AUParameterValueToLinear requires a v2 AudioUnit
        // handle, which AUParameter does not expose. Apply the advertised
        // display transform while preserving the endpoints exactly.
        guard value.isFinite, validRange(minimum: minimum, maximum: maximum) else { return 0 }
        if value <= minimum { return 0 }
        if value >= maximum { return 1 }

        let scale = displayScale(flags: flags, minimum: minimum, maximum: maximum)
        let lower = scale.forward(minimum)
        let upper = scale.forward(maximum)
        let displayed = scale.forward(value)
        guard lower.isFinite, upper.isFinite, displayed.isFinite, upper != lower else {
            return affinePosition(for: value, minimum: minimum, maximum: maximum)
        }
        return clamp((displayed - lower) / (upper - lower))
    }

    public static func parameterValue(
        at position: Double,
        minimum: Double,
        maximum: Double,
        flags: AudioUnitParameterOptions
    ) -> Double {
        guard position.isFinite, validRange(minimum: minimum, maximum: maximum) else { return minimum }
        if position <= 0 { return minimum }
        if position >= 1 { return maximum }

        let scale = displayScale(flags: flags, minimum: minimum, maximum: maximum)
        let lower = scale.forward(minimum)
        let upper = scale.forward(maximum)
        guard lower.isFinite, upper.isFinite, upper != lower else {
            return affineValue(at: position, minimum: minimum, maximum: maximum)
        }
        let value = scale.inverse(lower + position * (upper - lower))
        guard value.isFinite else {
            return affineValue(at: position, minimum: minimum, maximum: maximum)
        }
        return min(maximum, max(minimum, value))
    }

    private enum DisplayScale {
        case linear, squareRoot, squared, cubed, cubeRoot, exponential, logarithmic

        func forward(_ value: Double) -> Double {
            switch self {
            case .linear: return value
            case .squareRoot: return value.sign == .minus ? -sqrt(abs(value)) : sqrt(value)
            case .squared: return value.sign == .minus ? -(value * value) : value * value
            case .cubed: return value * value * value
            case .cubeRoot: return value.sign == .minus ? -pow(abs(value), 1.0 / 3.0) : pow(value, 1.0 / 3.0)
            case .exponential: return exp(value)
            case .logarithmic: return log(value)
            }
        }

        func inverse(_ value: Double) -> Double {
            switch self {
            case .linear: return value
            case .squareRoot: return value.sign == .minus ? -(value * value) : value * value
            case .squared: return value.sign == .minus ? -sqrt(abs(value)) : sqrt(value)
            case .cubed: return value.sign == .minus ? -pow(abs(value), 1.0 / 3.0) : pow(value, 1.0 / 3.0)
            case .cubeRoot: return value * value * value
            case .exponential: return log(value)
            case .logarithmic: return exp(value)
            }
        }
    }

    private static func displayScale(
        flags: AudioUnitParameterOptions,
        minimum: Double,
        maximum: Double
    ) -> DisplayScale {
        switch flags.intersection(.flag_DisplayMask) {
        case .flag_DisplaySquareRoot: return .squareRoot
        case .flag_DisplaySquared: return .squared
        case .flag_DisplayCubed: return .cubed
        case .flag_DisplayCubeRoot: return .cubeRoot
        case .flag_DisplayExponential: return .exponential
        case .flag_DisplayLogarithmic:
            // A logarithmic transform is undefined at or across zero. Linear
            // fallback remains continuous, reversible, and endpoint preserving.
            return minimum > 0 && maximum > 0 ? .logarithmic : .linear
        default: return .linear
        }
    }

    private static func affinePosition(for value: Double, minimum: Double, maximum: Double) -> Double {
        clamp((value - minimum) / (maximum - minimum))
    }

    private static func affineValue(at position: Double, minimum: Double, maximum: Double) -> Double {
        minimum + clamp(position) * (maximum - minimum)
    }

    private static func validRange(minimum: Double, maximum: Double) -> Bool {
        minimum.isFinite && maximum.isFinite && maximum > minimum
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}
