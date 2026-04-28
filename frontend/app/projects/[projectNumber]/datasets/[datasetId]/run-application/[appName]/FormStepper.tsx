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
    <nav className="mb-6">
      <ol className="flex items-center">
        {steps.map((step, index) => {
          const isCompleted = index < currentStepIndex;
          const isCurrent = index === currentStepIndex;
          const isClickable = !!onStepClick;

          return (
            <li key={step.id} className="flex items-center">
              {/* Entire step as clickable button */}
              <button
                type="button"
                onClick={() => isClickable && onStepClick(index)}
                disabled={!isClickable}
                className={`
                  flex items-center transition-colors rounded-lg px-2 py-1 -mx-2
                  ${isClickable ? 'hover:bg-gray-100 cursor-pointer' : 'cursor-default'}
                `}
              >
                {/* Step circle */}
                <span
                  className={`
                    flex items-center justify-center w-8 h-8 rounded-full text-sm font-medium
                    ${isCurrent
                      ? 'bg-brand-600 text-white'
                      : isCompleted
                        ? 'bg-brand-100 text-brand-700'
                        : 'bg-gray-200 text-gray-500'
                    }
                  `}
                >
                  {isCompleted ? (
                    <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                      <path
                        fillRule="evenodd"
                        d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                        clipRule="evenodd"
                      />
                    </svg>
                  ) : (
                    index + 1
                  )}
                </span>

                {/* Step label */}
                <span
                  className={`ml-2 text-sm font-medium ${
                    isCurrent ? 'text-brand-700' : isCompleted ? 'text-brand-600' : 'text-gray-500'
                  }`}
                >
                  {step.title}
                </span>
              </button>

              {/* Connector line */}
              {index < steps.length - 1 && (
                <div
                  className={`w-12 h-0.5 mx-3 ${
                    isCompleted ? 'bg-brand-300' : 'bg-gray-200'
                  }`}
                />
              )}
            </li>
          );
        })}
      </ol>
    </nav>
  );
}
