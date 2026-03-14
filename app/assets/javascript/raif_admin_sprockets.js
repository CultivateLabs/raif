// Sprockets entry point for Raif Admin.
// This is bundled by esbuild into app/assets/builds/raif_admin_sprockets.js
// and provides a self-contained Stimulus setup for host apps that don't use importmaps.
import { Application, Controller } from "@hotwired/stimulus"

// Make Controller available globally so the imported controller files can extend it
window.Stimulus = { Controller: Controller }

const application = Application.start()

import JudgeConfigController from "./raif/admin/judge_config_controller"
application.register("raif--judge-config", JudgeConfigController)

import SelectAllCheckboxesController from "./raif/admin/select_all_checkboxes_controller"
application.register("raif--select-all-checkboxes", SelectAllCheckboxesController)

import CostEstimateController from "./raif/admin/cost_estimate_controller"
application.register("raif--cost-estimate", CostEstimateController)

import TomSelectController from "./raif/admin/tom_select_controller"
application.register("raif--tom-select", TomSelectController)
