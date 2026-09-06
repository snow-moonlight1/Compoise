
import React from 'react';

interface CheckboxProps {
  checked: boolean;
  onChange: () => void;
  className?: string;
}

export const Checkbox: React.FC<CheckboxProps> = ({ checked, onChange, className }) => (
  <button
    role="checkbox"
    aria-checked={checked}
    onClick={(e) => { e.stopPropagation(); onChange(); }}
    className={`rounded-md border-2 transition-all duration-200 flex-none flex items-center justify-center ${
      checked
        ? 'bg-primary border-primary text-white'
        : 'bg-transparent border-slate-300 dark:border-slate-500 hover:border-primary text-transparent'
    } ${className || 'w-5 h-5'}`}
  >
    <svg 
      className={`w-3.5 h-3.5 transition-transform duration-200 ${checked ? 'scale-100' : 'scale-0'}`} 
      fill="none" 
      viewBox="0 0 24 24" 
      stroke="currentColor" 
      strokeWidth={3}
    >
      <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
    </svg>
  </button>
);
