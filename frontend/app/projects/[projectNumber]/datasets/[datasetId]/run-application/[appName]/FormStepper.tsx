import { ParamGroup } from '@/lib/types';

interface FormStepperProps {
  steps: ParamGroup[];
  currentStepIndex: number;
  onStepClick?: (index: number) => void;
}

export default function FormStepper({
  steps,
  currentStepIndex,
  onStepClick,
}: FormStepperProps) {
  return (
    <nav className="border-b border-gray-200">
      <ol className="flex gap-6">
        {steps.map((step, index) => {
          const isCurrent = index === currentStepIndex;

          return (
            <li key={step.id}>
              <button
                type="button"
                onClick={() => onStepClick?.(index)}
                className={`pb-4 text-base font-semibold border-b-[3px] transition-colors cursor-pointer ${
                  isCurrent
                    ? 'border-brand-600 text-brand-600'
                    : 'border-gray-300 text-gray-500 hover:text-gray-700 hover:border-gray-400'
                }`}
              >
                {step.title}
              </button>
            </li>
          );
        })}
      </ol>
    </nav>
  );
}
