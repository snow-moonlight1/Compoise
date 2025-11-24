import React, { useState } from 'react';
import { Task, SubTask } from '../types';
import { CalendarIcon, SplitIcon, FlagIcon, PlusIcon, TrashIcon, XIcon, PencilIcon } from './Icons';
import { Checkbox } from './ui/Checkbox';

interface TaskCardProps {
  task: Task;
  onDragStart: (e: React.DragEvent, task: Task) => void;
  onDelete: (id: string) => void;
  onDecompose: (task: Task) => void;
  onUpdate: (task: Task) => void;
  onParentCheck: (task: Task) => void;
  colors: { border: string, text: string };
  t: any;
  isSelectionMode: boolean;
  isSelected: boolean;
  onToggleSelect: (id: string) => void;
  onEdit: (task: Task, subTaskId?: string) => void;
}

export const TaskCard: React.FC<TaskCardProps> = ({ 
  task, 
  onDragStart, 
  onDelete, 
  onDecompose,
  onUpdate,
  onParentCheck,
  colors,
  t,
  isSelectionMode,
  isSelected,
  onToggleSelect,
  onEdit
}) => {
  
  const [newSubtask, setNewSubtask] = useState('');
  const [isAddingSub, setIsAddingSub] = useState(false);

  const calculateDaysLeft = (timestamp?: number) => {
    if (!timestamp) return null;
    return Math.ceil((timestamp - Date.now()) / (1000 * 60 * 60 * 24));
  };

  const daysLeft = calculateDaysLeft(task.deadline);
  
  const getDeadlineColor = (days: number) => {
    if (days < 0) return 'text-red-500 font-bold';
    if (days <= 2) return 'text-orange-500 font-bold';
    return 'text-slate-400';
  };

  const handleAddSubtask = () => {
    if (!newSubtask.trim()) return;
    const sub: SubTask = { id: crypto.randomUUID(), title: newSubtask, completed: false };
    onUpdate({ ...task, subtasks: [...(task.subtasks || []), sub] });
    setNewSubtask('');
    setIsAddingSub(false);
  };

  const toggleSubtask = (subId: string) => {
    if (!task.subtasks) return;
    const updatedSubs = task.subtasks.map(s => s.id === subId ? { ...s, completed: !s.completed } : s);
    onUpdate({ ...task, subtasks: updatedSubs });
  };

  const deleteSubtask = (subId: string) => {
    if (!task.subtasks) return;
    const updatedSubs = task.subtasks.filter(s => s.id !== subId);
    onUpdate({ ...task, subtasks: updatedSubs });
  };
  
  const toggleLongTerm = () => {
     onUpdate({ ...task, isLongTerm: !task.isLongTerm });
  };

  return (
    <div
      draggable={!isSelectionMode}
      onDragStart={(e) => onDragStart(e, task)}
      onClick={() => isSelectionMode && onToggleSelect(task.id)}
      className={`neu-btn cursor-grab active:cursor-grabbing group relative overflow-hidden flex flex-col gap-2 rounded-2xl
        mb-3 p-3 border border-slate-200/50 dark:border-slate-700/50 max-h-96
        ${isSelected ? 'ring-2 ring-primary bg-primary/5' : ''}
      `}
    >
      {task.isLongTerm && !task.subtasks?.length && (
        <div className="absolute top-0 left-0 w-1 h-full bg-yellow-400/50" />
      )}
      
      {/* Parent Task Header */}
      <div className="flex justify-between items-start gap-3 w-full">
        {isSelectionMode ? (
          <div className={`w-6 h-6 rounded border-2 flex-none flex items-center justify-center transition-colors mt-[1.5px] ${isSelected ? 'bg-primary border-primary text-white' : 'border-slate-400'}`}>
             {isSelected && <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={3} d="M5 13l4 4L19 7" /></svg>}
          </div>
        ) : (
          <Checkbox 
            checked={task.completed} 
            onChange={() => onParentCheck(task)}
            className="w-6 h-6 mt-[1.5px]" 
          />
        )}
        
        <div className="flex-1 min-w-0">
           <div className="relative inline-block">
               <span className={`text-sm font-bold break-words leading-tight transition-colors duration-500 ease-in-out relative z-0
                  ${task.completed ? 'text-gray-400 dark:text-gray-600' : 'text-slate-700 dark:text-slate-200'}
               `}>
                {task.title}
               </span>
               <span 
                 className={`absolute left-0 top-1/2 h-[2px] bg-slate-400/80 dark:bg-slate-500/80 block transition-all duration-500 ease-out z-10 pointer-events-none`}
                 style={{ width: task.completed ? '100%' : '0%' }}
               />
           </div>
        </div>

        {/* Meta Section: Deadline + Actions */}
        <div className="flex items-center gap-2 flex-none pt-0.5">
            {/* Right-aligned deadline */}
            {daysLeft !== null && !task.completed && (
             <div className={`text-xs flex items-center gap-1 ${getDeadlineColor(daysLeft)} whitespace-nowrap`}>
               {daysLeft < 0 ? t.overdue : daysLeft === 0 ? t.today : `${daysLeft}${t.daysLeft}`}
               <CalendarIcon size={10} />
             </div>
           )}

            {!isSelectionMode && (
              <div className="flex items-center gap-1 opacity-60 hover:opacity-100 transition-opacity ml-1">
                {task.isLongTerm && !task.subtasks?.length && (
                  <button 
                    onClick={(e) => { e.stopPropagation(); onDecompose(task); }}
                    className="text-yellow-500 hover:scale-110 transition-transform p-1"
                    title={t.decompose}
                  >
                    <SplitIcon size={14} />
                  </button>
                )}
                 <button 
                  onClick={(e) => { e.stopPropagation(); toggleLongTerm(); }}
                  className={`hover:text-primary transition-colors p-1 ${task.isLongTerm ? 'text-yellow-500' : 'text-slate-400'}`}
                  title={t.toggleLongTerm}
                >
                  <FlagIcon size={14} />
                </button>
                <button 
                  onClick={(e) => { e.stopPropagation(); onEdit(task); }}
                  className="text-slate-400 hover:text-primary transition-colors p-1"
                  title={t.editTask}
                >
                  <PencilIcon size={14} />
                </button>
                <button 
                  onClick={(e) => { e.stopPropagation(); setIsAddingSub(!isAddingSub); }}
                  className="text-slate-400 hover:text-primary transition-colors p-1"
                  title={t.addSubtask}
                >
                  <PlusIcon size={14} />
                </button>
                <button 
                  onClick={(e) => { e.stopPropagation(); onDelete(task.id); }}
                  className="text-red-400 hover:scale-110 transition-transform p-1"
                  title={t.deleteBoard}
                >
                  <TrashIcon size={14} />
                </button>
              </div>
            )}
        </div>
      </div>

      {/* Subtasks List */}
      {task.subtasks && task.subtasks.length > 0 && (
        <div className="mt-1 pl-3 border-l-2 border-slate-200 dark:border-slate-700 space-y-2 animate-fade-in origin-top">
          {task.subtasks.map(sub => {
             const subDays = calculateDaysLeft(sub.deadline);
             return (
                <div 
                  key={sub.id} 
                  className="flex items-start gap-2 text-xs group/sub transition-all duration-300 ease-in-out overflow-hidden opacity-100"
                >
                  <button 
                    onClick={(e) => { e.stopPropagation(); toggleSubtask(sub.id); }}
                    className={`w-4 h-4 mt-0.5 rounded border transition-colors flex-none flex items-center justify-center ${
                      sub.completed 
                        ? 'bg-slate-400 border-slate-400' 
                        : 'bg-transparent border-slate-400 hover:border-primary'
                    }`}
                  >
                     <svg 
                      className={`w-3 h-3 text-white transition-transform duration-200 ${sub.completed ? 'scale-100' : 'scale-0'}`} 
                      fill="none" 
                      viewBox="0 0 24 24" 
                      stroke="currentColor" 
                      strokeWidth={4}
                    >
                      <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
                    </svg>
                  </button>

                  <div className="flex-1 min-w-0">
                    <span className="relative inline-block leading-tight pt-0.5">
                        <span className={`transition-colors duration-500 ease-in-out relative z-0
                            ${sub.completed ? 'text-gray-400 dark:text-gray-600' : 'text-slate-600 dark:text-slate-300'}
                        `}>
                          {sub.title}
                        </span>
                        <span 
                           className={`absolute left-0 top-1/2 h-[1.5px] bg-slate-400/80 dark:bg-slate-500/80 block transition-all duration-500 ease-out z-10 pointer-events-none`}
                           style={{ width: sub.completed ? '100%' : '0%' }}
                         />
                    </span>
                  </div>
                  
                  {subDays !== null && !sub.completed && (
                     <span className={`text-[10px] mt-0.5 ${getDeadlineColor(subDays)}`}>
                        {subDays}d
                     </span>
                  )}
                  
                  <button 
                     onClick={(e) => { e.stopPropagation(); onEdit(task, sub.id); }}
                     className="opacity-0 group-hover/sub:opacity-100 text-slate-400 hover:text-primary p-0.5 transition-opacity"
                  >
                    <PencilIcon size={10} />
                  </button>
                  <button 
                     onClick={(e) => { e.stopPropagation(); deleteSubtask(sub.id); }}
                     className="opacity-0 group-hover/sub:opacity-100 text-red-400 p-0.5 transition-opacity"
                  >
                    <XIcon size={10} />
                  </button>
                </div>
             );
          })}
        </div>
      )}

      {/* Add Subtask Input */}
      {isAddingSub && (
        <div className="mt-2 flex gap-1 items-center animate-fade-in">
          <input 
            autoFocus
            value={newSubtask}
            onChange={(e) => setNewSubtask(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && handleAddSubtask()}
            placeholder={t.addSubtask}
            className="flex-1 bg-white dark:bg-slate-700 text-xs p-1.5 rounded border border-slate-200 dark:border-slate-600 outline-none"
          />
          <button onClick={handleAddSubtask} className="text-primary hover:scale-110 transition-transform"><PlusIcon size={16}/></button>
        </div>
      )}
    </div>
  );
};