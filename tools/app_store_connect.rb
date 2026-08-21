#!/usr/bin/env ruby
# frozen_string_literal: true

# Minimal App Store Connect API helper for creating/looking up the Woven Rampart
# bundle ID and app record. Credentials are read from the shared environment;
# no token or private-key content is printed.

require "base64"
require "json"
require "net/http"
require "openssl"
require "time"
require "uri"

API_ROOT = "https://api.appstoreconnect.apple.com"

def b64url(value)
  Base64.urlsafe_encode64(value, padding: false)
end

def jwt_token
  key_id = ENV.fetch("APP_STORE_CONNECT_KEY_ID")
  issuer = ENV.fetch("APP_STORE_CONNECT_ISSUER_ID")
  key_path = ENV.fetch("APP_STORE_CONNECT_KEY_PATH")
  header = { "alg" => "ES256", "kid" => key_id, "typ" => "JWT" }
  now = Time.now.to_i
  payload = { "iss" => issuer, "iat" => now, "exp" => now + 1_200, "aud" => "appstoreconnect-v1" }
  signing_input = [header, payload].map { |part| b64url(JSON.generate(part)) }.join(".")
  key = OpenSSL::PKey::EC.new(File.read(key_path))
  der_signature = key.dsa_sign_asn1(OpenSSL::Digest::SHA256.digest(signing_input))
  sequence = OpenSSL::ASN1.decode(der_signature)
  r = sequence.value[0].value.to_s(2).rjust(32, "\0")[-32, 32]
  s = sequence.value[1].value.to_s(2).rjust(32, "\0")[-32, 32]
  "#{signing_input}.#{b64url(r + s)}"
end

def api_request(method, path, body = nil)
  uri = URI.join(API_ROOT, path)
  request_class = Net::HTTP.const_get(method.capitalize)
  request = request_class.new(uri)
  request["Authorization"] = "Bearer #{jwt_token}"
  request["Content-Type"] = "application/json"
  request.body = JSON.generate(body) if body
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  response = http.request(request)
  parsed = response.body.to_s.empty? ? {} : JSON.parse(response.body)
  unless response.is_a?(Net::HTTPSuccess)
    detail = parsed.fetch("errors", parsed).to_json[0, 1_000]
    abort "App Store Connect API #{response.code}: #{detail}"
  end
  parsed
end

def first_resource(response)
  data = response["data"]
  data.is_a?(Array) ? data.first : data
end

def lookup(bundle_id)
  bundle_response = api_request("get", "/v1/bundleIds?filter[identifier]=#{URI.encode_www_form_component(bundle_id)}")
  app_response = api_request("get", "/v1/apps?filter[bundleId]=#{URI.encode_www_form_component(bundle_id)}")
  bundle = first_resource(bundle_response)
  app = first_resource(app_response)
  puts JSON.generate(
    "bundle_id" => bundle_id,
    "bundle_resource_id" => bundle && bundle["id"],
    "app_resource_id" => app && app["id"],
    "app_name" => app && app.dig("attributes", "name"),
    "app_store_state" => app && app.dig("attributes", "appStoreState"),
  )
end

def ensure_app(bundle_id, app_name, sku, locale)
  bundle_response = api_request("get", "/v1/bundleIds?filter[identifier]=#{URI.encode_www_form_component(bundle_id)}")
  bundle = first_resource(bundle_response)
  unless bundle
    bundle = first_resource(api_request("post", "/v1/bundleIds", {
      "data" => {
        "type" => "bundleIds",
        "attributes" => { "identifier" => bundle_id, "name" => app_name, "platform" => "IOS" },
      },
    }))
    puts "Created iOS bundle identifier #{bundle_id} (#{bundle["id"]})"
  else
    puts "iOS bundle identifier already exists: #{bundle_id} (#{bundle["id"]})"
  end

  app_response = api_request("get", "/v1/apps?filter[bundleId]=#{URI.encode_www_form_component(bundle_id)}")
  app = first_resource(app_response)
  unless app
    app = first_resource(api_request("post", "/v1/apps", {
      "data" => {
        "type" => "apps",
        "attributes" => { "name" => app_name, "sku" => sku, "primaryLocale" => locale },
        "relationships" => { "bundleId" => { "data" => { "type" => "bundleIds", "id" => bundle["id"] } } },
      },
    }))
    puts "Created App Store Connect app #{app_name} (#{app["id"]})"
  else
    puts "App Store Connect app already exists: #{app_name} (#{app["id"]})"
  end
end

def list_certificates
  response = api_request("get", "/v1/certificates?limit=200")
  rows = Array(response["data"]).map do |resource|
    {
      "id" => resource["id"],
      "certificate_type" => resource.dig("attributes", "certificateType"),
      "display_name" => resource.dig("attributes", "displayName"),
      "expiration_date" => resource.dig("attributes", "expirationDate"),
    }
  end
  puts JSON.generate(rows)
end

def list_profiles
  response = api_request("get", "/v1/profiles?limit=200")
  rows = Array(response["data"]).map do |resource|
    {
      "id" => resource["id"],
      "name" => resource.dig("attributes", "name"),
      "profile_state" => resource.dig("attributes", "profileState"),
      "profile_type" => resource.dig("attributes", "profileType"),
      "expiration_date" => resource.dig("attributes", "expirationDate"),
    }
  end
  puts JSON.generate(rows)
end

def list_builds(app_id)
  response = api_request(
    "get",
    "/v1/builds?filter[app]=#{URI.encode_www_form_component(app_id)}&sort=-uploadedDate&limit=20",
  )
  rows = Array(response["data"]).map do |resource|
    {
      "id" => resource["id"],
      "version" => resource.dig("attributes", "version"),
      "build_version" => resource.dig("attributes", "buildVersion"),
      "processing_state" => resource.dig("attributes", "processingState"),
      "uploaded_date" => resource.dig("attributes", "uploadedDate"),
      "expiration_date" => resource.dig("attributes", "expirationDate"),
    }
  end
  puts JSON.generate(rows)
end

def create_certificate(csr_path, output_path)
  csr = Base64.strict_encode64(File.binread(csr_path))
  response = api_request("post", "/v1/certificates", {
    "data" => {
      "type" => "certificates",
      "attributes" => { "certificateType" => "IOS_DISTRIBUTION", "csrContent" => csr },
    },
  })
  resource = first_resource(response)
  content = resource.dig("attributes", "certificateContent")
  abort "Apple did not return certificate content" unless content
  File.binwrite(output_path, Base64.decode64(content))
  File.chmod(0o600, output_path)
  puts JSON.generate(
    "certificate_resource_id" => resource["id"],
    "certificate_type" => resource.dig("attributes", "certificateType"),
    "expiration_date" => resource.dig("attributes", "expirationDate"),
    "output_path" => output_path,
  )
end

def download_certificate(certificate_id, output_path)
  response = api_request("get", "/v1/certificates/#{URI.encode_www_form_component(certificate_id)}")
  resource = first_resource(response)
  content = resource.dig("attributes", "certificateContent")
  abort "Apple did not return certificate content" unless content
  File.binwrite(output_path, Base64.decode64(content))
  File.chmod(0o600, output_path)
  puts JSON.generate(
    "certificate_resource_id" => resource["id"],
    "certificate_type" => resource.dig("attributes", "certificateType"),
    "expiration_date" => resource.dig("attributes", "expirationDate"),
    "output_path" => output_path,
  )
end

def create_profile(bundle_id, certificate_id, profile_name, output_path)
  bundle_response = api_request("get", "/v1/bundleIds?filter[identifier]=#{URI.encode_www_form_component(bundle_id)}")
  bundle = first_resource(bundle_response)
  abort "Bundle ID not found: #{bundle_id}" unless bundle
  response = api_request("post", "/v1/profiles", {
    "data" => {
      "type" => "profiles",
      "attributes" => { "name" => profile_name, "profileType" => "IOS_APP_STORE" },
      "relationships" => {
        "bundleId" => { "data" => { "type" => "bundleIds", "id" => bundle["id"] } },
        "certificates" => { "data" => [{ "type" => "certificates", "id" => certificate_id }] },
      },
    },
  })
  resource = first_resource(response)
  content = resource.dig("attributes", "profileContent")
  abort "Apple did not return profile content" unless content
  File.binwrite(output_path, Base64.decode64(content))
  File.chmod(0o600, output_path)
  puts JSON.generate(
    "profile_resource_id" => resource["id"],
    "profile_name" => resource.dig("attributes", "name"),
    "expiration_date" => resource.dig("attributes", "expirationDate"),
    "output_path" => output_path,
  )
end

command = ARGV.shift
bundle_id = ARGV.shift || "com.handstar.bingowar"
case command
when "lookup"
  lookup(bundle_id)
when "ensure"
  ensure_app(bundle_id, ARGV.shift || "Woven Rampart", ARGV.shift || "woven-rampart-ios-001", ARGV.shift || "en-US")
when "certificates"
  list_certificates
when "profiles"
  list_profiles
when "builds"
  list_builds(bundle_id)
when "create_certificate"
  create_certificate(bundle_id, ARGV.shift || abort("output path required"))
when "download_certificate"
  download_certificate(bundle_id, ARGV.shift || abort("output path required"))
when "create_profile"
  create_profile(
    bundle_id,
    ARGV.shift || abort("certificate resource id required"),
    ARGV.shift || "Woven Rampart App Store",
    ARGV.shift || abort("output path required"),
  )
else
  warn "Usage: app_store_connect.rb lookup [bundle_id]"
  warn "       app_store_connect.rb ensure [bundle_id] [app_name] [sku] [locale]"
  warn "       app_store_connect.rb certificates"
  warn "       app_store_connect.rb profiles"
  warn "       app_store_connect.rb builds [app_resource_id]"
  warn "       app_store_connect.rb create_certificate [csr_path] [output_path]"
  warn "       app_store_connect.rb download_certificate [certificate_id] [output_path]"
  warn "       app_store_connect.rb create_profile [bundle_id] [certificate_id] [name] [output_path]"
  exit 2
end
