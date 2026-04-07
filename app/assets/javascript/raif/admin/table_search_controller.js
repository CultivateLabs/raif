import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["input", "row"];

  filter() {
    const terms = this.inputTarget.value.toLowerCase().trim().split(/\s+/).filter(Boolean);

    this.rowTargets.forEach((row) => {
      const text = row.dataset.searchable || row.textContent.toLowerCase();
      const visible = terms.length === 0 || terms.every((term) => text.includes(term));
      row.style.display = visible ? "" : "none";
    });
  }
}
