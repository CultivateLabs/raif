import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["checkbox", "modelSelect", "judgeModelSelect", "judgeTypeSelect", "estimate"];
  static values = { pricing: Object };

  calculate() {
    if (!this.hasModelSelectTarget || !this.hasEstimateTarget) return;

    const modelKey = this.modelSelectTarget.value;
    const pricing = this.pricingValue[modelKey];

    if (!pricing) {
      this.hideEstimate();
      return;
    }

    const selected = this.checkboxTargets.filter((cb) => cb.checked);

    if (selected.length === 0) {
      this.hideEstimate();
      return;
    }

    let totalPromptTokens = 0;
    let totalCompletionTokens = 0;

    selected.forEach((cb) => {
      totalPromptTokens += parseInt(cb.dataset.promptTokens || 0, 10);
      totalCompletionTokens += parseInt(cb.dataset.completionTokens || 0, 10);
    });

    const taskInputCost = totalPromptTokens * pricing.input;
    const taskOutputCost = totalCompletionTokens * pricing.output;
    const taskTotalCost = taskInputCost + taskOutputCost;

    let judgeCost = null;
    const judgeType = this.hasJudgeTypeSelectTarget ? this.judgeTypeSelectTarget.value : "";
    if (judgeType) {
      const judgeModelKey = this.hasJudgeModelSelectTarget ? this.judgeModelSelectTarget.value : "";
      const judgePricing = this.pricingValue[judgeModelKey];

      if (judgePricing) {
        // Rough estimate: judge input ≈ prompt + completion tokens from the task, judge output ≈ 500 tokens
        const judgeInputTokens = totalPromptTokens + totalCompletionTokens;
        const judgeOutputTokens = selected.length * 500;
        judgeCost = judgeInputTokens * judgePricing.input + judgeOutputTokens * judgePricing.output;
      }
    }

    const totalCost = taskTotalCost + (judgeCost || 0);
    const avgTokens = Math.round((totalPromptTokens + totalCompletionTokens) / selected.length);

    let html = `<strong>Estimated cost: ${this.formatCurrency(totalCost)}</strong>`;
    html += `<br><small class="text-muted">Task runs: ${this.formatCurrency(taskTotalCost)} (${selected.length} tasks &times; ~${this.formatNumber(avgTokens)} tokens avg)`;
    if (judgeCost !== null) {
      html += `<br>Judge runs: ~${this.formatCurrency(judgeCost)}`;
    }
    html += "</small>";

    this.estimateTarget.innerHTML = html;
    this.estimateTarget.classList.remove("d-none");
  }

  hideEstimate() {
    this.estimateTarget.innerHTML = "";
    this.estimateTarget.classList.add("d-none");
  }

  formatCurrency(amount) {
    if (amount < 0.01) {
      return `$${amount.toFixed(4)}`;
    }
    return `$${amount.toFixed(2)}`;
  }

  formatNumber(num) {
    return num.toLocaleString();
  }
}
