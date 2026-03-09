import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["binary", "scored", "comparative", "summarization", "sharedOptions"];

  toggle(event) {
    const selectedType = event.target.value;
    const typeMap = {
      "Raif::Evals::LlmJudges::Binary": this.binaryTarget,
      "Raif::Evals::LlmJudges::Scored": this.scoredTarget,
      "Raif::Evals::LlmJudges::Comparative": this.comparativeTarget,
      "Raif::Evals::LlmJudges::Summarization": this.summarizationTarget,
    };

    Object.values(typeMap).forEach((el) => el.classList.add("d-none"));
    this.sharedOptionsTarget.classList.add("d-none");

    if (typeMap[selectedType]) {
      typeMap[selectedType].classList.remove("d-none");
      this.sharedOptionsTarget.classList.remove("d-none");
    }
  }
}
