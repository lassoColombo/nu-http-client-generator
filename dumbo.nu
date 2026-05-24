# Auto-generated client for dumbo v0.2.0
# Source: /Users/colombos/.config/nushell/modules/http-gen/example-openapi/dumbo.yaml
# Auth: --token flag or $env.DUMBO_TOKEN

const BASE_URL = "https://dumbo.k8s.elmec.ad"


# Root command for namespace resolution
export def main [] { print "dumbo v0.2.0 — 10 commands" }

# POST /api/v1/cloud-init/
# Body fields:
#   networkType: string (required) [dhcp, static]
#   otpVpn: string (required)
#   ipAddress: string
#   gateway: string
#   primaryDns: string
#   secondaryDns: string
export def "cloud-init create" [
  --base-url: string
  --token: string
  --auth-scheme: string
  --insecure(-k) # Skip TLS verification
  --body: record
] {
  let token_val = if ($token | is-not-empty) { $token } else { $env.DUMBO_TOKEN? | default "" }
  let scheme = ($auth_scheme | default "jwt")
  let prefix = match $scheme { "jwt" => "JWT", "bearer" => "Bearer", "basic" => "Basic", "static" => "STATIC", "private-token" => "PRIVATE-TOKEN", _ => "JWT" }
  let headers = if ($token_val | is-empty) { {} } else if $scheme == "private-token" { {PRIVATE-TOKEN: $token_val} } else { {Authorization: $"($prefix) ($token_val)"} }
  let base = ($base_url | default $BASE_URL)
  let url = $"($base)/api/v1/cloud-init/"
  let full_url = $url
  let resp = if $insecure { http post --headers $headers --content-type application/json --full --allow-errors --insecure $full_url $body } else { http post --headers $headers --content-type application/json --full --allow-errors $full_url $body }
  if $resp.status >= 400 { error make { msg: $"HTTP ($resp.status): ($resp.body)" } } else { $resp.body }
}

# GET /api/v1/dmilog/
export def "dmilog list" [
  --base-url: string
  --token: string
  --auth-scheme: string
  --insecure(-k) # Skip TLS verification
  --customer: int
  --domain: string
  --name: string
  --ordering: string # Which field to use when ordering the results.
  --private-ip: string
  --search: string # A search term.
  --vpn-ip: string
] {
  let token_val = if ($token | is-not-empty) { $token } else { $env.DUMBO_TOKEN? | default "" }
  let scheme = ($auth_scheme | default "jwt")
  let prefix = match $scheme { "jwt" => "JWT", "bearer" => "Bearer", "basic" => "Basic", "static" => "STATIC", "private-token" => "PRIVATE-TOKEN", _ => "JWT" }
  let headers = if ($token_val | is-empty) { {} } else if $scheme == "private-token" { {PRIVATE-TOKEN: $token_val} } else { {Authorization: $"($prefix) ($token_val)"} }
  let base = ($base_url | default $BASE_URL)
  let url = $"($base)/api/v1/dmilog/"
  let qp = {customer: $customer, domain: $domain, name: $name, ordering: $ordering, private_ip: $private_ip, search: $search, vpn_ip: $vpn_ip} | transpose k v | where { $in.v != null } | each { $"($in.k)=($in.v)" } | str join "&"
  let full_url = if ($qp | is-empty) { $url } else { $"($url)?($qp)" }
  let resp = if $insecure { http get --headers $headers --full --allow-errors --insecure $full_url } else { http get --headers $headers --full --allow-errors $full_url }
  if $resp.status >= 400 { error make { msg: $"HTTP ($resp.status): ($resp.body)" } } else { $resp.body }
}

# GET /api/v1/dmilog/{name}/
export def "dmilog get" [
  name: string
  --base-url: string
  --token: string
  --auth-scheme: string
  --insecure(-k) # Skip TLS verification
] {
  let token_val = if ($token | is-not-empty) { $token } else { $env.DUMBO_TOKEN? | default "" }
  let scheme = ($auth_scheme | default "jwt")
  let prefix = match $scheme { "jwt" => "JWT", "bearer" => "Bearer", "basic" => "Basic", "static" => "STATIC", "private-token" => "PRIVATE-TOKEN", _ => "JWT" }
  let headers = if ($token_val | is-empty) { {} } else if $scheme == "private-token" { {PRIVATE-TOKEN: $token_val} } else { {Authorization: $"($prefix) ($token_val)"} }
  let base = ($base_url | default $BASE_URL)
  let url = $"($base)/api/v1/dmilog/($name)/"
  let full_url = $url
  let resp = if $insecure { http get --headers $headers --full --allow-errors --insecure $full_url } else { http get --headers $headers --full --allow-errors $full_url }
  if $resp.status >= 400 { error make { msg: $"HTTP ($resp.status): ($resp.body)" } } else { $resp.body }
}

# PUT /api/v1/dmilog/{name}/
# Body fields:
#   name: string (required)
#   activate: array
#   deactivate: array
#   commit_message: string (required)
export def "dmilog update" [
  name: string
  --base-url: string
  --token: string
  --auth-scheme: string
  --insecure(-k) # Skip TLS verification
  --body: record
] {
  let token_val = if ($token | is-not-empty) { $token } else { $env.DUMBO_TOKEN? | default "" }
  let scheme = ($auth_scheme | default "jwt")
  let prefix = match $scheme { "jwt" => "JWT", "bearer" => "Bearer", "basic" => "Basic", "static" => "STATIC", "private-token" => "PRIVATE-TOKEN", _ => "JWT" }
  let headers = if ($token_val | is-empty) { {} } else if $scheme == "private-token" { {PRIVATE-TOKEN: $token_val} } else { {Authorization: $"($prefix) ($token_val)"} }
  let base = ($base_url | default $BASE_URL)
  let url = $"($base)/api/v1/dmilog/($name)/"
  let full_url = $url
  let resp = if $insecure { http put --headers $headers --content-type application/json --full --allow-errors --insecure $full_url $body } else { http put --headers $headers --content-type application/json --full --allow-errors $full_url $body }
  if $resp.status >= 400 { error make { msg: $"HTTP ($resp.status): ($resp.body)" } } else { $resp.body }
}

# POST /api/v1/hooks/chart
# Body fields:
#   version: string (required)
#   project_id: integer (required)
export def "hooks-chart create" [
  --base-url: string
  --token: string
  --auth-scheme: string
  --insecure(-k) # Skip TLS verification
  --body: record
] {
  let token_val = if ($token | is-not-empty) { $token } else { $env.DUMBO_TOKEN? | default "" }
  let scheme = ($auth_scheme | default "jwt")
  let prefix = match $scheme { "jwt" => "JWT", "bearer" => "Bearer", "basic" => "Basic", "static" => "STATIC", "private-token" => "PRIVATE-TOKEN", _ => "JWT" }
  let headers = if ($token_val | is-empty) { {} } else if $scheme == "private-token" { {PRIVATE-TOKEN: $token_val} } else { {Authorization: $"($prefix) ($token_val)"} }
  let base = ($base_url | default $BASE_URL)
  let url = $"($base)/api/v1/hooks/chart"
  let full_url = $url
  let resp = if $insecure { http post --headers $headers --content-type application/json --full --allow-errors --insecure $full_url $body } else { http post --headers $headers --content-type application/json --full --allow-errors $full_url $body }
  if $resp.status >= 400 { error make { msg: $"HTTP ($resp.status): ($resp.body)" } } else { $resp.body }
}

# POST /api/v1/hooks/dmilog
# Body fields:
#   sha: string (required)
#   project_id: integer (required)
#   commit_message: string (required)
export def "hooks-dmilog create" [
  --base-url: string
  --token: string
  --auth-scheme: string
  --insecure(-k) # Skip TLS verification
  --body: record
] {
  let token_val = if ($token | is-not-empty) { $token } else { $env.DUMBO_TOKEN? | default "" }
  let scheme = ($auth_scheme | default "jwt")
  let prefix = match $scheme { "jwt" => "JWT", "bearer" => "Bearer", "basic" => "Basic", "static" => "STATIC", "private-token" => "PRIVATE-TOKEN", _ => "JWT" }
  let headers = if ($token_val | is-empty) { {} } else if $scheme == "private-token" { {PRIVATE-TOKEN: $token_val} } else { {Authorization: $"($prefix) ($token_val)"} }
  let base = ($base_url | default $BASE_URL)
  let url = $"($base)/api/v1/hooks/dmilog"
  let full_url = $url
  let resp = if $insecure { http post --headers $headers --content-type application/json --full --allow-errors --insecure $full_url $body } else { http post --headers $headers --content-type application/json --full --allow-errors $full_url $body }
  if $resp.status >= 400 { error make { msg: $"HTTP ($resp.status): ($resp.body)" } } else { $resp.body }
}

# Generic endpoint to retrieve status of any RQ job
# given queue name + job id.
export def "jobs get" [
  job_id: string
  queue_name: string
  --base-url: string
  --token: string
  --auth-scheme: string
  --insecure(-k) # Skip TLS verification
] {
  let token_val = if ($token | is-not-empty) { $token } else { $env.DUMBO_TOKEN? | default "" }
  let scheme = ($auth_scheme | default "jwt")
  let prefix = match $scheme { "jwt" => "JWT", "bearer" => "Bearer", "basic" => "Basic", "static" => "STATIC", "private-token" => "PRIVATE-TOKEN", _ => "JWT" }
  let headers = if ($token_val | is-empty) { {} } else if $scheme == "private-token" { {PRIVATE-TOKEN: $token_val} } else { {Authorization: $"($prefix) ($token_val)"} }
  let base = ($base_url | default $BASE_URL)
  let url = $"($base)/api/v1/jobs/($queue_name)/($job_id)/"
  let full_url = $url
  let resp = if $insecure { http get --headers $headers --full --allow-errors --insecure $full_url } else { http get --headers $headers --full --allow-errors $full_url }
  if $resp.status >= 400 { error make { msg: $"HTTP ($resp.status): ($resp.body)" } } else { $resp.body }
}

# GET /api/v1/me/permissions/services
export def "me-permissions-services get" [
  --base-url: string
  --token: string
  --auth-scheme: string
  --insecure(-k) # Skip TLS verification
] {
  let token_val = if ($token | is-not-empty) { $token } else { $env.DUMBO_TOKEN? | default "" }
  let scheme = ($auth_scheme | default "jwt")
  let prefix = match $scheme { "jwt" => "JWT", "bearer" => "Bearer", "basic" => "Basic", "static" => "STATIC", "private-token" => "PRIVATE-TOKEN", _ => "JWT" }
  let headers = if ($token_val | is-empty) { {} } else if $scheme == "private-token" { {PRIVATE-TOKEN: $token_val} } else { {Authorization: $"($prefix) ($token_val)"} }
  let base = ($base_url | default $BASE_URL)
  let url = $"($base)/api/v1/me/permissions/services"
  let full_url = $url
  let resp = if $insecure { http get --headers $headers --full --allow-errors --insecure $full_url } else { http get --headers $headers --full --allow-errors $full_url }
  if $resp.status >= 400 { error make { msg: $"HTTP ($resp.status): ($resp.body)" } } else { $resp.body }
}

# GET /api/v1/services/
export def "services list" [
  --base-url: string
  --token: string
  --auth-scheme: string
  --insecure(-k) # Skip TLS verification
  --ordering: string # Which field to use when ordering the results.
  --search: string # A search term.
] {
  let token_val = if ($token | is-not-empty) { $token } else { $env.DUMBO_TOKEN? | default "" }
  let scheme = ($auth_scheme | default "jwt")
  let prefix = match $scheme { "jwt" => "JWT", "bearer" => "Bearer", "basic" => "Basic", "static" => "STATIC", "private-token" => "PRIVATE-TOKEN", _ => "JWT" }
  let headers = if ($token_val | is-empty) { {} } else if $scheme == "private-token" { {PRIVATE-TOKEN: $token_val} } else { {Authorization: $"($prefix) ($token_val)"} }
  let base = ($base_url | default $BASE_URL)
  let url = $"($base)/api/v1/services/"
  let qp = {ordering: $ordering, search: $search} | transpose k v | where { $in.v != null } | each { $"($in.k)=($in.v)" } | str join "&"
  let full_url = if ($qp | is-empty) { $url } else { $"($url)?($qp)" }
  let resp = if $insecure { http get --headers $headers --full --allow-errors --insecure $full_url } else { http get --headers $headers --full --allow-errors $full_url }
  if $resp.status >= 400 { error make { msg: $"HTTP ($resp.status): ($resp.body)" } } else { $resp.body }
}

# GET /status
export def "status get" [
  --base-url: string
  --token: string
  --auth-scheme: string
  --insecure(-k) # Skip TLS verification
] {
  let token_val = if ($token | is-not-empty) { $token } else { $env.DUMBO_TOKEN? | default "" }
  let scheme = ($auth_scheme | default "jwt")
  let prefix = match $scheme { "jwt" => "JWT", "bearer" => "Bearer", "basic" => "Basic", "static" => "STATIC", "private-token" => "PRIVATE-TOKEN", _ => "JWT" }
  let headers = if ($token_val | is-empty) { {} } else if $scheme == "private-token" { {PRIVATE-TOKEN: $token_val} } else { {Authorization: $"($prefix) ($token_val)"} }
  let base = ($base_url | default $BASE_URL)
  let url = $"($base)/status"
  let full_url = $url
  let resp = if $insecure { http get --headers $headers --full --allow-errors --insecure $full_url } else { http get --headers $headers --full --allow-errors $full_url }
  if $resp.status >= 400 { error make { msg: $"HTTP ($resp.status): ($resp.body)" } } else { $resp.body }
}
