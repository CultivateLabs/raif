import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["header", "body"];

  sort(event) {
    const th = event.currentTarget;
    const colIndex = parseInt(th.dataset.colIndex, 10);
    const type = th.dataset.sortType || "string";
    const currentDir = th.dataset.sortDir;
    const newDir = currentDir === "asc" ? "desc" : "asc";

    // Reset all headers
    this.headerTargets.forEach((header) => {
      header.dataset.sortDir = "";
      header.querySelector(".sort-indicator")?.remove();
    });

    th.dataset.sortDir = newDir;

    // Add sort indicator
    const indicator = document.createElement("span");
    indicator.className = "sort-indicator ms-1";
    indicator.textContent = newDir === "asc" ? "\u25B2" : "\u25BC";
    th.appendChild(indicator);

    const rows = Array.from(this.bodyTarget.querySelectorAll("tr"));
    rows.sort((a, b) => {
      const aCell = a.children[colIndex];
      const bCell = b.children[colIndex];
      if (!aCell || !bCell) return 0;

      let aVal = (aCell.dataset.sortValue || aCell.textContent).trim();
      let bVal = (bCell.dataset.sortValue || bCell.textContent).trim();

      if (type === "number") {
        aVal = parseFloat(aVal) || 0;
        bVal = parseFloat(bVal) || 0;
      } else {
        aVal = aVal.toLowerCase();
        bVal = bVal.toLowerCase();
      }

      if (aVal < bVal) return newDir === "asc" ? -1 : 1;
      if (aVal > bVal) return newDir === "asc" ? 1 : -1;
      return 0;
    });

    rows.forEach((row) => this.bodyTarget.appendChild(row));
  }
}
