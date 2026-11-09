require "test_helper"

class RouteHostTest < ActionDispatch::IntegrationTest
  test "admin host serves the login page" do
    host! "app.upright.localhost"
    get "/session/new"
    assert_response :success
  end

  test "admin host root routes to the engine and requires login" do
    host! "app.upright.localhost"
    get "/"
    assert_response :redirect
    assert_match %r{/session/new\z}, response.location
  end

  test "site host root routes to the engine and sends visitors to admin login" do
    host! "fra.upright.localhost"
    get "/"
    assert_response :redirect
    assert_match %r{\Ahttp://app\.upright\.localhost(:\d+)?/session/new\z}, response.location
  end

  test "site host does not serve session/new" do
    host! "fra.upright.localhost"
    get "/session/new"
    assert_response :not_found
  end
end
