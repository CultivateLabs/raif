import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    if (typeof TomSelect === "undefined") return;

    const blankOption = this.element.querySelector('option[value=""]');
    const placeholder = blankOption ? blankOption.textContent : "";

    this.tomSelect = new TomSelect(this.element, {
      allowEmptyOption: true,
      placeholder: placeholder,
    });

    if (blankOption) {
      blankOption.textContent = "";
    }
  }

  disconnect() {
    if (this.tomSelect) {
      this.tomSelect.destroy();
    }
  }
}
