# ============================================================
# QuickSight data source + dataset over the CUR table (optional)
# Enable after the Glue crawler has run once and created the table.
# The QuickSight service role also needs access to the CUR bucket
# (QuickSight console > Manage QuickSight > Security & permissions).
# ============================================================
locals {
  quicksight_principal = "arn:aws:quicksight:${var.aws_region}:${data.aws_caller_identity.current.account_id}:user/default/${var.quicksight_user}"
}

resource "aws_quicksight_data_source" "athena_source" {
  count          = var.enable_quicksight ? 1 : 0
  data_source_id = "finops-athena"
  name           = "FinOps Athena"
  type           = "ATHENA"

  parameters {
    athena {
      work_group = aws_athena_workgroup.this.name
    }
  }

  permission {
    principal = local.quicksight_principal
    actions = [
      "quicksight:DescribeDataSource",
      "quicksight:DescribeDataSourcePermissions",
      "quicksight:PassDataSource",
      "quicksight:UpdateDataSource",
      "quicksight:UpdateDataSourcePermissions",
      "quicksight:DeleteDataSource"
    ]
  }
}

resource "aws_quicksight_data_set" "cur_dataset" {
  count       = var.enable_quicksight ? 1 : 0
  data_set_id = "finops-cur-dataset"
  name        = "FinOps CUR Dataset"
  import_mode = "DIRECT_QUERY"

  physical_table_map {
    physical_table_map_id = "cur"
    relational_table {
      data_source_arn = aws_quicksight_data_source.athena_source[0].arn
      catalog         = "AwsDataCatalog"
      schema          = aws_glue_catalog_database.cur_db.name
      name            = local.cur_table

      input_columns {
        name = "line_item_usage_account_id"
        type = "STRING"
      }
      input_columns {
        name = "line_item_product_code"
        type = "STRING"
      }
      input_columns {
        name = "line_item_usage_type"
        type = "STRING"
      }
      input_columns {
        name = "line_item_resource_id"
        type = "STRING"
      }
      input_columns {
        name = "line_item_usage_start_date"
        type = "DATETIME"
      }
      input_columns {
        name = "line_item_unblended_cost"
        type = "DECIMAL"
      }
      input_columns {
        name = "year"
        type = "STRING"
      }
      input_columns {
        name = "month"
        type = "STRING"
      }
    }
  }

  permissions {
    principal = local.quicksight_principal
    actions = [
      "quicksight:DescribeDataSet",
      "quicksight:DescribeDataSetPermissions",
      "quicksight:PassDataSet",
      "quicksight:DescribeIngestion",
      "quicksight:ListIngestions",
      "quicksight:UpdateDataSet",
      "quicksight:UpdateDataSetPermissions",
      "quicksight:DeleteDataSet"
    ]
  }
}
