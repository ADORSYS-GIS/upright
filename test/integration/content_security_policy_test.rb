require "test_helper"

class ContentSecurityPolicyTest < ActionDispatch::IntegrationTest
  setup do
    host! "app.upright.localhost"
  end

  test "an off-origin form action is blocked" do
    get "/session/new"

    assert_response :success
    sources = directive_sources(response.headers["Content-Security-Policy"], "form-action")
    assert sources, "form-action is absent, and it does not fall back to default-src"

    document_origin = "http://app.upright.localhost"
    assert_select "form[action]" do |forms|
      forms.each do |form|
        assert allows_form_action?(sources, form["action"], document_origin),
          "sign-in form action #{form["action"]} is outside form-action"
      end
    end
    assert_not allows_form_action?(sources, "https://example.com/capture", document_origin)
  end

  test "inline style elements stay nonced while style attributes stay allowed" do
    get "/session/new"

    policy = response.headers["Content-Security-Policy"]
    style_src = directive_sources(policy, "style-src")
    style_src_attr = directive_sources(policy, "style-src-attr")

    assert_not_includes style_src, "'unsafe-inline'"
    assert style_src.any? { |source| source.start_with?("'nonce-") }
    assert_includes style_src, "'sha256-47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU='"
    assert_includes style_src, "'sha256-CssDN67+wdcVeOo1+UBDlTtUvWjUmBJyiyqqRJHhrTQ='"
    assert_equal [ "'unsafe-inline'" ], style_src_attr
  end

  private
    def directive_sources(policy, name)
      directive = policy.to_s.split(";").map(&:strip).find { |part| part.start_with?("#{name} ") }
      return if directive.nil?

      directive.split[1..]
    end

    def allows_form_action?(sources, target, document_origin)
      destination = URI.parse(target)
      document = URI.parse(document_origin)
      same_origin = destination.host.nil? || (destination.host == document.host && destination.scheme.in?([ nil, document.scheme ]))

      sources.any? do |source|
        case source
        when "'self'" then same_origin
        when "'none'" then false
        when "*" then true
        else
          scheme = destination.scheme || document.scheme
          host = destination.host || document.host
          source == "#{scheme}:" || source == "#{scheme}://#{host}" || source == target
        end
      end
    end
end
