import SwiftUI

struct OnboardingView: View {
    @Binding var showOnboarding: Bool // This binds to hasCompletedOnboarding
    @State private var currentPage = 0
    
    var body: some View {
        TabView(selection: $currentPage) {
            OnboardingPage(
                image: "pawprint.circle.fill",
                title: "Your Pet's Best Friend",
                description: "Effortlessly track food, water, and daily care to ensure your pet stays happy and healthy.",
                color: .accentColor
            )
            .tag(0)
            
            OnboardingPage(
                image: "drop.fill",
                title: "Track What Matters",
                description: "Never wonder \"did I feed the dog?\" again. Monitor food bowls and water levels at a simple glance.",
                color: .blue
            )
            .tag(1)
            
            OnboardingPage(
                image: "timer",
                title: "Tailored to Your Pet",
                description: "You know your pet best. Tell us how long a bowl of food or water usually lasts, and we'll handle the timely reminders.",
                color: .orange
            )
            .tag(2)
            
            OnboardingPage(
                image: "lightbulb.fill",
                title: "Smart Estimations",
                description: "Simply estimate how many days a bag of food lasts or how often you refill the water bowl. You can always fine-tune this later!",
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
                    .font(.title3) // Slightly larger for better readability
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
                Text("All Set!")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("You're ready to start tracking. Let's make sure your pet gets the best care possible.")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Button {
                // Set hasCompletedOnboarding to TRUE to dismiss the sheet permanently
                showOnboarding = true 
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
    OnboardingView(showOnboarding: .constant(false))
}
