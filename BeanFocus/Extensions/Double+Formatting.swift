import Foundation

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }

    var asPercentInt: String {
        "\(Int(self.rounded()))%"
    }

    var asOneDecimal: String {
        String(format: "%.1f", self)
    }

    var asBPM: String {
        "\(Int(self.rounded())) bpm"
    }
}
