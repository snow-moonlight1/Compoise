import React from 'react';

interface ToggleSwitchProps {
  checked: boolean;
  onChange: () => void;
  ariaLabel?: string;
}

export const ToggleSwitch: React.FC<ToggleSwitchProps> = ({ checked, onChange, ariaLabel }) => (
  <button
    role="switch"
    aria-checked={checked}
    aria-label={ariaLabel}
    onClick={onChange}
    className={`w-12 h-7 rounded-full relative transition-colors duration-200 focus:outline-none flex-none ${checked ? 'bg-primary' : 'bg-slate-300 dark:bg-slate-600'}`}
  >
    <div
      className="absolute top-1 left-1 w-5 h-5 rounded-full bg-white shadow-md transition-transform duration-300 ease-spring"
      style={{ transform: checked ? 'translateX(20px)' : 'translateX(0)' }}
    />
  </button>
);
