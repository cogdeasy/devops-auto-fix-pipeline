import jenkins.model.*

def instance = Jenkins.getInstance()

// Install useful plugins would go here, but for local dev
// the base LTS image is sufficient for API access

// Disable CSRF for simpler API access from MCP (local dev only)
instance.setCrumbIssuer(null)

instance.save()
println("=== Jenkins setup complete ===")
