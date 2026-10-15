import SwiftUI

enum Theme {
    static let navy = Color(red: 0.08, green: 0.15, blue: 0.20)
    static let teal = Color(red: 0.0, green: 0.48, blue: 0.45)
    static let mint = Color(red: 0.86, green: 0.95, blue: 0.92)
    static let background = Color(red: 0.97, green: 0.97, blue: 0.95)
    static let secondary = Color(red: 0.37, green: 0.43, blue: 0.45)
    static let line = Color(red: 0.88, green: 0.90, blue: 0.88)
}
struct Surface<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View { content.padding(20).background(.white).clipShape(RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1)) }
}
