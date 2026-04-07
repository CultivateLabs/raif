import "@hotwired/turbo-rails"
import { application } from "controllers/application"

import JudgeConfigController from "raif/admin/judge_config_controller"
application.register("raif--judge-config", JudgeConfigController)

import SelectAllCheckboxesController from "raif/admin/select_all_checkboxes_controller"
application.register("raif--select-all-checkboxes", SelectAllCheckboxesController)

import CostEstimateController from "raif/admin/cost_estimate_controller"
application.register("raif--cost-estimate", CostEstimateController)

import TomSelectController from "raif/admin/tom_select_controller"
application.register("raif--tom-select", TomSelectController)

import TableSearchController from "raif/admin/table_search_controller"
application.register("raif--table-search", TableSearchController)

import SortableTableController from "raif/admin/sortable_table_controller"
application.register("raif--sortable-table", SortableTableController)
