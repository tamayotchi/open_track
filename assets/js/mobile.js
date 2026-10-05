const keyboardInputTypes = new Set(["text", "email", "password", "search", "tel", "url", "number"])

function isEditingText(element) {
  if (!element || element.disabled || element.readOnly) return false

  return element.isContentEditable || element.tagName === "TEXTAREA" ||
    (element.tagName === "INPUT" && keyboardInputTypes.has(element.type))
}

export function isKeyboardOpen(viewport, layoutHeight, editing) {
  // Pinch zoom also shrinks the visual viewport; don't mistake it for a keyboard.
  return Boolean(viewport && editing && Math.abs(viewport.scale - 1) < 0.05 &&
    layoutHeight - viewport.height > 150)
}

export function setupMobileViewport(win = window, doc = document) {
  const viewport = win.visualViewport
  if (!viewport) return

  let frame
  const update = () => {
    const layoutHeight = Math.max(win.innerHeight, doc.documentElement.clientHeight)
    doc.documentElement.classList.toggle("keyboard-open",
      isKeyboardOpen(viewport, layoutHeight, isEditingText(doc.activeElement)))
  }
  const schedule = () => {
    win.cancelAnimationFrame(frame)
    frame = win.requestAnimationFrame(update)
  }

  viewport.addEventListener("resize", schedule)
  doc.addEventListener("focusin", schedule)
  doc.addEventListener("focusout", schedule)
  doc.addEventListener("visibilitychange", schedule)
  win.addEventListener("pageshow", schedule)
  update()
}
