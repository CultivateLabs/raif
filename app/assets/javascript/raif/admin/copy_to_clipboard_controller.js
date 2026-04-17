import { Controller } from "@hotwired/stimulus";

const COPY_ICON = `<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" fill="currentColor" viewBox="0 0 16 16" aria-hidden="true">
<path d="M4 1.5H3a2 2 0 0 0-2 2V14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V3.5a2 2 0 0 0-2-2h-1v1h1a1 1 0 0 1 1 1V14a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V3.5a1 1 0 0 1 1-1h1v-1z"/>
<path d="M9.5 1a.5.5 0 0 1 .5.5v1a.5.5 0 0 1-.5.5h-3a.5.5 0 0 1-.5-.5v-1a.5.5 0 0 1 .5-.5h3zm-3-1A1.5 1.5 0 0 0 5 1.5v1A1.5 1.5 0 0 0 6.5 4h3A1.5 1.5 0 0 0 11 2.5v-1A1.5 1.5 0 0 0 9.5 0h-3z"/>
</svg>`;

const CHECK_ICON = `<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" fill="currentColor" viewBox="0 0 16 16" aria-hidden="true">
<path d="M13.854 3.646a.5.5 0 0 1 0 .708l-7 7a.5.5 0 0 1-.708 0l-3.5-3.5a.5.5 0 1 1 .708-.708L6.5 10.293l6.646-6.647a.5.5 0 0 1 .708 0z"/>
</svg>`;

export default class extends Controller {
  connect() {
    this.attachAll();

    this.observer = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        for (const node of mutation.addedNodes) {
          if (!(node instanceof Element)) continue;
          if (node.matches && node.matches("pre")) {
            this.attach(node);
          }
          if (node.querySelectorAll) {
            node.querySelectorAll("pre").forEach((pre) => this.attach(pre));
          }
        }
      }
    });

    this.observer.observe(this.element, { childList: true, subtree: true });
  }

  disconnect() {
    if (this.observer) {
      this.observer.disconnect();
      this.observer = null;
    }
  }

  attachAll() {
    this.element.querySelectorAll("pre").forEach((pre) => this.attach(pre));
  }

  attach(pre) {
    if (pre.dataset.raifCopyAttached === "true") return;
    if (pre.closest("[data-raif-copy-skip]")) return;
    pre.dataset.raifCopyAttached = "true";

    const wrapper = document.createElement("div");
    wrapper.className = "raif-copyable-pre";
    const classesToCopy = ["mb-0", "mb-2", "mb-3", "mt-1", "mt-2", "mt-3"];
    classesToCopy.forEach((cls) => {
      if (pre.classList.contains(cls)) {
        wrapper.classList.add(cls);
        pre.classList.remove(cls);
      }
    });

    pre.parentNode.insertBefore(wrapper, pre);
    wrapper.appendChild(pre);

    const button = document.createElement("button");
    button.type = "button";
    button.className = "btn btn-sm btn-outline-secondary raif-copy-btn";
    button.setAttribute("aria-label", "Copy to clipboard");
    button.setAttribute("title", "Copy to clipboard");
    button.innerHTML = COPY_ICON;
    button.addEventListener("click", (event) => {
      event.preventDefault();
      this.copy(pre, button);
    });

    wrapper.appendChild(button);
  }

  async copy(pre, button) {
    const text = pre.textContent;
    let succeeded = false;

    if (navigator.clipboard && window.isSecureContext) {
      try {
        await navigator.clipboard.writeText(text);
        succeeded = true;
      } catch (_err) {
        succeeded = false;
      }
    }

    if (!succeeded) {
      succeeded = this.fallbackCopy(text);
    }

    this.showFeedback(button, succeeded);
  }

  fallbackCopy(text) {
    const textarea = document.createElement("textarea");
    textarea.value = text;
    textarea.setAttribute("readonly", "");
    textarea.style.position = "absolute";
    textarea.style.left = "-9999px";
    document.body.appendChild(textarea);
    textarea.select();
    let ok = false;
    try {
      ok = document.execCommand("copy");
    } catch (_err) {
      ok = false;
    }
    document.body.removeChild(textarea);
    return ok;
  }

  showFeedback(button, succeeded) {
    const originalHTML = button.innerHTML;
    const originalTitle = button.getAttribute("title");
    button.innerHTML = succeeded ? CHECK_ICON : "!";
    button.setAttribute("title", succeeded ? "Copied" : "Copy failed");
    button.classList.add(succeeded ? "raif-copy-btn-success" : "raif-copy-btn-error");

    clearTimeout(button._raifCopyTimer);
    button._raifCopyTimer = setTimeout(() => {
      button.innerHTML = originalHTML;
      button.setAttribute("title", originalTitle || "Copy to clipboard");
      button.classList.remove("raif-copy-btn-success", "raif-copy-btn-error");
    }, 1500);
  }
}
