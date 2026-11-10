require "test_helper"

class AlertmanagerProxyViewTest < ActionView::TestCase
  helper do
    def alertmanager_proxy_path
      Upright::Engine.routes.url_helpers.alertmanager_proxy_path
    end
  end

  test "Alertmanager iframe uses a slash-terminated proxy URL for relative assets" do
    render template: "upright/alertmanager_proxy/show"

    assert_select "iframe[src='/alertmanager/']"
  end
end
