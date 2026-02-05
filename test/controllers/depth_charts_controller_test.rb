require "test_helper"

class DepthChartsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get depth_charts_index_url
    assert_response :success
  end

  test "should get show" do
    get depth_charts_show_url
    assert_response :success
  end
end
