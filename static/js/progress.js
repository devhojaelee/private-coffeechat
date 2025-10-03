/**
 * Progress Indicator Component
 * Manages the 4-step workflow progress display
 */

class ProgressIndicator {
    constructor() {
        this.steps = ['정보입력', '이메일인증', '시간선택', '완료'];
        this.currentStep = 1;
    }

    /**
     * Initialize progress indicator with current step
     * @param {number} stepNumber - Current step (1-4)
     */
    init(stepNumber) {
        if (stepNumber >= 1 && stepNumber <= 4) {
            this.currentStep = stepNumber;
            this.updateDisplay();
        }
    }

    /**
     * Update the progress indicator display
     */
    updateDisplay() {
        const stepElements = document.querySelectorAll('.progress-step');

        stepElements.forEach((element, index) => {
            const stepNum = index + 1;
            element.classList.remove('active', 'completed');

            if (stepNum < this.currentStep) {
                element.classList.add('completed');
                element.setAttribute('aria-current', 'false');
            } else if (stepNum === this.currentStep) {
                element.classList.add('active');
                element.setAttribute('aria-current', 'step');
            } else {
                element.setAttribute('aria-current', 'false');
            }
        });
    }

    /**
     * Move to next step
     */
    nextStep() {
        if (this.currentStep < 4) {
            this.currentStep++;
            this.updateDisplay();
        }
    }

    /**
     * Move to previous step
     */
    prevStep() {
        if (this.currentStep > 1) {
            this.currentStep--;
            this.updateDisplay();
        }
    }

    /**
     * Jump to specific step
     * @param {number} stepNumber - Target step (1-4)
     */
    goToStep(stepNumber) {
        if (stepNumber >= 1 && stepNumber <= 4) {
            this.currentStep = stepNumber;
            this.updateDisplay();
        }
    }

    /**
     * Get current step number
     * @returns {number} Current step (1-4)
     */
    getCurrentStep() {
        return this.currentStep;
    }
}

// Auto-initialize on DOM ready
document.addEventListener('DOMContentLoaded', function() {
    // Check if progress stepper exists on page
    const progressStepper = document.querySelector('.progress-stepper');
    if (!progressStepper) return;

    // Initialize progress indicator
    window.progressIndicator = new ProgressIndicator();

    // Auto-detect current step from data attribute or default to 1
    const currentStep = parseInt(progressStepper.dataset.currentStep) || 1;
    window.progressIndicator.init(currentStep);
});
