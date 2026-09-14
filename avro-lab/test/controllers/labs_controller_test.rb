require "test_helper"

class LabsControllerTest < ActionDispatch::IntegrationTest
  test "index lists experiments with a link to the avro lab" do
    get root_path

    assert_response :success
    assert_select "h1", "DDIA Labs"
    assert_select "a[href='/avro']"
  end

  test "avro editor is served at /avro" do
    get "/avro"

    assert_response :success
    assert_select "textarea#json_text"
  end
end
