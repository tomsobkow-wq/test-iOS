import SwiftUI

struct OnboardingView: View {
    @Binding var showOnboarding: Bool
    @State private var currentPage = 0
    
    var body: some View {
        TabView(selection: $currentPage) {
            OnboardingPage(
                image: "pawprint.circle.fill", // Using system images for now, can be replaced with custom assets
                title: "Welcome to Pet Tracker!",
                description: "This app helps you keep your animals happy by tracking their food and water.",
                color: .accentColor
            )
            .tag(0)
            
            OnboardingPage(
                image: "drop.fill",
                title: "Simple Tracking",
                description: "We track simple things like: Is the water bottle empty? Is the food bowl low?",
                color: .blue
            )
            .tag(1)
            
            OnboardingPage(
                image: "timer",
                title: "You Are The Expert",
                description: "To help you, we need your help first! You need to estimate how long it takes for your pet to finish their food or water.",
                color: .orange
            )
            .tag(2)
            
            OnboardingPage(
                image: "lightbulb.fill",
                title: "How to Estimate",
                description: "Simple ways to estimate:\n• How many days does a bag of food last?\n• How often do you refill the water bottle?",
                color: .yellow
            )
            .tag(3)
            
            FinalOnboardingPage(showOnboarding: $showOnboarding)
                .tag(4)

        }
        .tabViewStyle(.page)
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}

struct OnboardingPage: View {
    let image: String
    let title: String
    let description: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: image)
                .font(.system(size: 80))
                .foregroundColor(color)
                .padding()
                .background(
                    Circle()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                )
            
            VStack(spacing: 16) {
                Text(title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text(description)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Spacer()
        }
        .padding()
    }
}

struct FinalOnboardingPage: View {
    @Binding var showOnboarding: Bool
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
                .padding()
                .background(
                    Circle()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                )
            
            VStack(spacing: 16) {
                Text("Ready?")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Ready to keep your pet happy? Let's go!")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Button {
                showOnboarding = false
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(height: 55)
                    .frame(maxWidth: .infinity)
                    .background(Color.accentColor)
                    .cornerRadius(16)
                    .padding(.horizontal, 32)
            }
            
            Spacer()
        }
        .padding()
    }
}

#Preview {
    OnboardingView(showOnboarding: .constant(true))
}
