// Raif admin-only Stimulus controllers
import { application } from "controllers/application"

import JudgeConfigController from "raif/admin/judge_config_controller"
application.register("raif--judge-config", JudgeConfigController)

import SelectAllCheckboxesController from "raif/admin/select_all_checkboxes_controller"
application.register("raif--select-all-checkboxes", SelectAllCheckboxesController)
