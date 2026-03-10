import jenkins.model.*
import hudson.security.*
import jenkins.security.*
import jenkins.security.apitoken.*

def instance = Jenkins.getInstance()

// Create admin user
def hudsonRealm = new HudsonPrivateSecurityRealm(false)
hudsonRealm.createAccount("admin", "admin123")
instance.setSecurityRealm(hudsonRealm)

// Allow admin full access
def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)

instance.save()

// Create API token for the admin user
def user = User.getById("admin", false)
def tokenStore = user.getProperty(ApiTokenProperty.class)
def result = tokenStore.tokenStore.generateNewToken("mcp-token")
def tokenValue = result.plainValue

// Write token to a file so we can retrieve it
new File("/var/jenkins_home/mcp-api-token.txt").text = tokenValue

println("=== Jenkins MCP API Token: ${tokenValue} ===")
