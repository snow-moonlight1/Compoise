

import React from 'react';
import { Task, QuadrantType } from '../types';
import { TaskCard } from './TaskCard';
import { TrashIcon } from './Icons';

interface QuadrantProps {
  type: QuadrantType;
  title: string;
  shortTitle: string;
  colorCode: string;
  tasks: Task[];
  onDrop: (e: React.DragEvent, quadrant: QuadrantType) => void;
  onDragOver: (e: React.DragEvent) => void;
  onDragStart: (e: React.DragEvent, task: Task) => void;
  onDelete: (id: string) => void;
  onClear: (type: QuadrantType) => void;
  onDecompose: (task: Task) => void;
  onUpdate: (task: Task) => void;
  onParentCheck: (task: Task) => void;
  t: any;
  isSelectionMode: boolean;
  selectedTaskIds: Set<string>;
  onToggleSelect: (id: string) => void;
  onEdit: (task: Task, subTaskId?: string) => void;
}

export const Quadrant: React.FC<QuadrantProps> = ({ 
  type, 
  title, 
  shortTitle, 
  colorCode, 
  tasks, 
  onDrop, 
  onDragOver, 
  onDragStart,
  onDelete,
  onClear,
  onDecompose,
  onUpdate,
  onParentCheck,
  t,
  isSelectionMode,
  selectedTaskIds,
  onToggleSelect,
  onEdit
}) => {
  const getColorStyles = (code: string) => {
    switch(code) {
      case 'q1': return { border: 'border-q1', text: 'text-q1' };
      case 'q2': return { border: 'border-q2', text: 'text-q2' };
      case 'q3': return { border: 'border-q3', text: 'text-q3' };
      case 'q4': return { border: 'border-q4', text: 'text-q4' };
      default: return { border: 'border-slate-400', text: 'text-slate-400' };
    }
  };
  
  const styles = getColorStyles(colorCode);

  return (
    <div 
      onDrop={(e) => onDrop(e, type)}
      onDragOver={onDragOver}
      className="flex flex-col h-full gap-3 min-h-0"
    >
      {/* Header Outside the Box */}
      <div className="flex justify-between items-center px-1 flex-none h-6 md:h-8">
        <div className="flex items-center gap-2">
          <div className={`w-2 h-2 rounded-full bg-${colorCode}`}></div>
          <h3 className="font-bold text-slate-600 dark:text-slate-300 text-sm md:text-base truncate hidden md:block">{title}</h3>
          <h3 className="font-bold text-slate-600 dark:text-slate-300 text-sm md:text-base truncate block md:hidden">{shortTitle}</h3>
        </div>
        <div className="flex items-center gap-2">
            {tasks.length > 0 && (
               <button 
                 onClick={(e) => { 
                   e.stopPropagation(); 
                   e.preventDefault();
                   onClear(type); 
                 }}
                 className="p-1 text-slate-400 hover:text-red-400 transition-colors"
                 title={t.clearQuadrant}
               >
                 <TrashIcon size={16} />
               </button>
            )}
            <span className="text-xs font-bold text-slate-400 bg-slate-200/50 dark:bg-slate-700/50 px-2 py-0.5 rounded-full">
              {tasks.length}
            </span>
        </div>
      </div>
      
      {/* Task Container */}
      <div className="neu-pressed rounded-2xl flex-1 overflow-hidden relative">
        <div className="h-full overflow-y-auto custom-scrollbar p-2">
          {tasks.length === 0 ? (
            <div className="h-full flex items-center justify-center text-slate-400 text-xs italic select-none animate-fade-in">
              {t.empty}
            </div>
          ) : (
            tasks.map(task => (
              <TaskCard 
                key={task.id} 
                task={task} 
                onDragStart={onDragStart} 
                onDelete={onDelete}
                onDecompose={onDecompose}
                onUpdate={onUpdate}
                onParentCheck={onParentCheck}
                colors={styles}
                t={t}
                isSelectionMode={isSelectionMode}
                isSelected={selectedTaskIds.has(task.id)}
                onToggleSelect={onToggleSelect}
                onEdit={onEdit}
              />
            ))
          )}
        </div>
      </div>
    </div>
  );
};
