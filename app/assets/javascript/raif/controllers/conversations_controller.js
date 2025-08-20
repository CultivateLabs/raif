import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    requestAnimationFrame(() => this.scrollToBottom());
  }

  scrollToBottom() {
    this.element.scrollTo({ top: this.element.scrollHeight });
  }
}