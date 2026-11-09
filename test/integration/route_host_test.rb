require "test_helper"

class RouteHostTest < ActionDispatch::IntegrationTest
  test "admin host routes to Upright engine without 404 on session/new" do
    host! "app.upright.eudi-adorsys.com"
    get "/session/new"
    assert_response :success
  end

  test "site host routes to Upright engine without 404 on session/new" do
    host! "fra.upright.eudi-adorsys.com"
    get "/session/new"
    assert_response :success
  end

  test "root path resolves on admin host" do
    host! "app.upright.eudi-adorsys.com"
    get "/"
    assert_response :success
  end

  test "root path resolves on site host" do
    host! "fra.upright.eudi-adorsys.com"
    get "/"
    assert_response :success
  end
end
