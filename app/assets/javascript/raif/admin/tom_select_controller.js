import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    if (typeof TomSelect === "undefined") return;

    const isMultiple = this.element.hasAttribute("multiple");
    const blankOption = this.element.querySelector('option[value=""]');
    const placeholder = blankOption ? blankOption.textContent : "";

    const options = {
      allowEmptyOption: !isMultiple,
      placeholder: placeholder,
      plugins: {},
    };

    if (isMultiple) {
      options.plugins.remove_button = { title: "Remove" };
    }

    this.tomSelect = new TomSelect(this.element, options);

    if (blankOption && !isMultiple) {
      blankOption.textContent = "";
    }
  }

  disconnect() {
    if (this.tomSelect) {
      this.tomSelect.destroy();
    }
  }
}
