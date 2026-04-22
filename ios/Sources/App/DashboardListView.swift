import SwiftUI

struct DashboardListView: View {
    let dashboards: [DashboardSummary]
    @Binding var selectedDashboardId: String?

    var body: some View {
        if dashboards.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("No dashboards yet")
                    .font(.headline)
                Text("Open Claude Desktop and ask it to make one for you:\n“Show me Stripe MRR on my Home Screen.”")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        } else {
            List(dashboards) { dash in
                Button {
                    selectedDashboardId = dash.id
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(dash.name).font(.headline)
                            if let themeId = dash.themeId {
                                Text(themeId).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
