import React, { useEffect, useRef, useState } from 'react';
import { XIcon } from '../Icons';

export interface ModalProps {
  isOpen: boolean;
  onClose: () => void;
  children: React.ReactNode;
  title?: string;
  hideClose?: boolean;
}

const FOCUSABLE_SELECTOR = 'button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

export const Modal: React.FC<ModalProps> = ({ isOpen, onClose, children, title, hideClose = false }) => {
  const [shouldRender, setShouldRender] = useState(isOpen);
  const [isAnimating, setIsAnimating] = useState(isOpen);
  const panelRef = useRef<HTMLDivElement>(null);
  const previouslyFocused = useRef<HTMLElement | null>(null);
  const onCloseRef = useRef(onClose);
  onCloseRef.current = onClose;

  useEffect(() => {
    if (isOpen) {
      setShouldRender(true);
      setIsAnimating(true);
    } else {
      setIsAnimating(false);
      const timer = setTimeout(() => {
        setShouldRender(false);
      }, 300); // Match animation duration
      return () => clearTimeout(timer);
    }
  }, [isOpen]);

  // Focus management: focus trap, Esc to close, restore focus on close
  useEffect(() => {
    if (!isOpen || !shouldRender) return;
    const panel = panelRef.current;
    if (!panel) return;

    previouslyFocused.current = document.activeElement as HTMLElement;
    if (!panel.contains(document.activeElement)) {
      const first = panel.querySelector<HTMLElement>(FOCUSABLE_SELECTOR);
      (first || panel).focus();
    }

    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.stopPropagation();
        onCloseRef.current();
        return;
      }
      if (e.key !== 'Tab') return;
      const focusables: HTMLElement[] = Array.from(panel.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTOR));
      if (focusables.length === 0) return;
      const first = focusables[0];
      const last = focusables[focusables.length - 1];
      const active = document.activeElement;
      if (e.shiftKey && (active === first || !panel.contains(active))) {
        e.preventDefault();
        last.focus();
      } else if (!e.shiftKey && (active === last || !panel.contains(active))) {
        e.preventDefault();
        first.focus();
      }
    };

    document.addEventListener('keydown', onKeyDown, true);
    return () => {
      document.removeEventListener('keydown', onKeyDown, true);
      previouslyFocused.current?.focus?.();
    };
  }, [isOpen, shouldRender]);

  if (!shouldRender) return null;

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label={title}
      onClick={(e) => { if (e.target === e.currentTarget) onCloseRef.current(); }}
      className={`fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40 backdrop-blur-sm ${isAnimating ? 'animate-fade-in' : 'animate-fade-out'}`}
    >
      <div
        ref={panelRef}
        tabIndex={-1}
        className={`neu-flat dark:text-slate-200 rounded-2xl w-full max-w-md p-6 relative overflow-hidden max-h-[90vh] flex flex-col shadow-2xl outline-none ${isAnimating ? 'animate-slide-up' : 'animate-slide-out'}`}
      >
        <div className="flex justify-between items-center mb-4 flex-none">
          {title && <h2 className="text-xl font-bold text-slate-800 dark:text-white">{title}</h2>}
          {!hideClose && (
            <button
              onClick={onClose}
              aria-label="Close"
              className="neu-btn p-2 rounded-full text-slate-500 hover:text-slate-700 dark:hover:text-slate-300 transition-colors absolute top-4 right-4"
            >
              <XIcon size={18} />
            </button>
          )}
        </div>
        <div className="flex-1 overflow-y-auto custom-scrollbar pr-2">
          {children}
        </div>
      </div>
    </div>
  );
};
