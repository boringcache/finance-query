group "boringcache" {
  targets = ["server", "mcp"]
}

group "gha-publish" {
  targets = ["server-gha-publish", "mcp-gha-publish"]
}

group "gha-restore" {
  targets = ["server-gha-restore", "mcp-gha-restore"]
}

target "common" {
  context = "."
  args = {
    CARGO_FEATURES = "translation"
  }
  output = ["type=docker"]
}

target "server" {
  inherits   = ["common"]
  dockerfile = "server/Dockerfile"
  tags       = ["financequery:v2-ci"]
}

target "mcp" {
  inherits   = ["common"]
  dockerfile = "finance-query-mcp/Dockerfile"
  tags       = ["financequery:mcp-ci"]
}

target "server-gha-publish" {
  inherits   = ["server"]
  cache-from = ["type=gha,scope=docker-server"]
  cache-to   = ["type=gha,mode=max,scope=docker-server"]
}

target "mcp-gha-publish" {
  inherits   = ["mcp"]
  cache-from = ["type=gha,scope=docker-mcp"]
  cache-to   = ["type=gha,mode=max,scope=docker-mcp"]
}

target "server-gha-restore" {
  inherits   = ["server"]
  cache-from = ["type=gha,scope=docker-server"]
}

target "mcp-gha-restore" {
  inherits   = ["mcp"]
  cache-from = ["type=gha,scope=docker-mcp"]
}
