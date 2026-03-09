import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["selectAll", "checkbox", "selectedCount", "batchButton"];
  static values = { batchButtonLabel: String };

  connect() {
    if (this.hasBatchButtonTarget) {
      this.batchButtonLabelValue = this.batchButtonTarget.textContent.trim();
    }
  }

  toggle() {
    const checked = this.selectAllTarget.checked;
    this.checkboxTargets.forEach((cb) => (cb.checked = checked));
    this.updateCount();
  }

  updateCount() {
    const count = this.checkboxTargets.filter((cb) => cb.checked).length;
    this.selectedCountTargets.forEach((el) => {
      el.textContent = count;
    });
    if (this.hasBatchButtonTarget) {
      this.batchButtonTarget.disabled = count === 0;
      this.batchButtonTarget.textContent =
        count > 0
          ? `${this.batchButtonLabelValue} (${count})`
          : this.batchButtonLabelValue;
    }
  }
}
