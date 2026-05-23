# frozen_string_literal: true

class Raif::ModelTools::ComplexTestTool < Raif::ModelTool
  tool_arguments_schema do
    string :title, description: "The title of the operation", minLength: 3

    object :settings, description: "Configuration settings" do
      boolean :enabled, description: "Whether the tool is enabled"
      integer :priority, description: "Priority level (1-10)", minimum: 1, maximum: 10
      array :tags, description: "Associated tags" do
        items type: "string"
      end
    end

    array :products, description: "List of products" do
      object do
        integer :id, description: "Product identifier"
        string :name, description: "Product name"
        number :price, description: "Product price", minimum: 0
      end
    end
  end

  example_model_invocation do
    {
      "name" => tool_name,
      "arguments" => {
        "title" => "Daily Inventory Update",
        "settings" => {
          "enabled" => true,
          "priority" => 5,
          "tags" => ["inventory", "daily-update", "retail"]
        },
        "items" => [
          { "id" => 101, "name" => "Wireless Mouse", "price" => 25.99 },
          { "id" => 102, "name" => "Keyboard", "price" => 45.0 },
          { "id" => 103, "name" => "USB-C Cable", "price" => 9.99 }
        ]
      }
    }
  end

  tool_description do
    "An example tool demonstrating complex schema capabilities"
  end

  def self.process_invocation(tool_invocation)
    # This would be the actual implementation
    # For demonstration purposes, just echo back the arguments
    tool_invocation.update!(
      result: {
        message: "Received complex example request",
        arguments: tool_invocation.tool_arguments
      }
    )

    tool_invocation.result
  end

  def self.format_result_for_llm(invocation)
    return "No results" unless invocation.result.present?

    "Successfully processed request for: #{invocation.tool_arguments["title"]}"
  end
end
