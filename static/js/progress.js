/**
 * Progress Indicator Component
 * Creates and manages the 4-step progress stepper
 * Steps: 1/4 정보입력 → 2/4 이메일인증 → 3/4 시간선택 → 4/4 완료
 */

(function() {
  'use strict';

  /**
   * Creates a progress stepper component
   * @param {number} currentStep - Current step (1-4)
   * @returns {HTMLElement} Progress stepper element
   */
  function createProgressStepper(currentStep) {
    const steps = [
      { number: 1, label: '정보입력' },
      { number: 2, label: '이메일인증' },
      { number: 3, label: '시간선택' },
      { number: 4, label: '완료' }
    ];

    const container = document.createElement('div');
    container.className = 'progress-stepper';
    container.setAttribute('role', 'progressbar');
    container.setAttribute('aria-valuemin', '1');
    container.setAttribute('aria-valuemax', '4');
    container.setAttribute('aria-valuenow', currentStep.toString());
    container.setAttribute('aria-label', `예약 진행 단계: ${currentStep}/4`);

    steps.forEach((step, index) => {
      // Create step element
      const stepEl = document.createElement('div');
      stepEl.className = 'progress-step';

      // Set aria-current for current step
      if (step.number === currentStep) {
        stepEl.setAttribute('aria-current', 'step');
      }

      // Create circle
      const circle = document.createElement('div');
      circle.className = 'progress-step-circle';

      if (step.number < currentStep) {
        circle.classList.add('completed');
        circle.innerHTML = '✓';
        circle.setAttribute('aria-label', `${step.label} 완료`);
      } else if (step.number === currentStep) {
        circle.classList.add('active');
        circle.textContent = step.number;
        circle.setAttribute('aria-label', `현재 단계: ${step.label}`);
      } else {
        circle.textContent = step.number;
        circle.setAttribute('aria-label', `${step.label} 대기 중`);
      }

      // Create label
      const label = document.createElement('div');
      label.className = 'progress-step-label';

      if (step.number < currentStep) {
        label.classList.add('completed');
      } else if (step.number === currentStep) {
        label.classList.add('active');
      }

      label.textContent = step.label;

      stepEl.appendChild(circle);
      stepEl.appendChild(label);
      container.appendChild(stepEl);

      // Add connector (except after last step)
      if (index < steps.length - 1) {
        const connector = document.createElement('div');
        connector.className = 'progress-connector';
        connector.setAttribute('aria-hidden', 'true');

        if (step.number < currentStep) {
          connector.classList.add('completed');
        }

        container.appendChild(connector);
      }
    });

    return container;
  }

  /**
   * Initializes the progress indicator on page load
   */
  function initProgressIndicator() {
    // Check if progress indicator should be shown on this page
    const progressContainer = document.querySelector('[data-progress-step]');

    if (progressContainer) {
      const currentStep = parseInt(progressContainer.getAttribute('data-progress-step'), 10);

      if (currentStep >= 1 && currentStep <= 4) {
        const stepper = createProgressStepper(currentStep);
        progressContainer.appendChild(stepper);
      }
    }
  }

  // Initialize when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initProgressIndicator);
  } else {
    initProgressIndicator();
  }

  // Export for manual initialization if needed
  window.ProgressIndicator = {
    create: createProgressStepper,
    init: initProgressIndicator
  };
})();
