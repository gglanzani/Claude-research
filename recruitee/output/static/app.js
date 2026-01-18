/**
 * Xebia Careers - Application Form Handler
 * Submits applications directly to Recruitee API
 */

(function() {
    'use strict';

    const RECRUITEE_API = 'https://xebiacareers.recruitee.com/api/offers';

    /**
     * Initialize the application form
     */
    function init() {
        const form = document.getElementById('application-form');
        if (!form) return;

        form.addEventListener('submit', handleSubmit);
    }

    /**
     * Handle form submission
     */
    async function handleSubmit(event) {
        event.preventDefault();

        const form = event.target;
        const submitBtn = form.querySelector('button[type="submit"]');
        const statusEl = document.getElementById('form-status');
        const offerSlug = form.dataset.offerSlug;

        if (!offerSlug) {
            showStatus(statusEl, 'error', 'Configuration error: Missing offer slug');
            return;
        }

        // Disable form during submission
        submitBtn.disabled = true;
        submitBtn.textContent = 'Submitting...';
        showStatus(statusEl, 'loading', 'Submitting your application...');

        try {
            const formData = buildFormData(form);
            const response = await submitApplication(offerSlug, formData);

            if (response.ok) {
                showStatus(statusEl, 'success',
                    'Thank you! Your application has been submitted successfully. We will be in touch soon.');
                form.reset();
            } else {
                const error = await response.json().catch(() => ({}));
                const message = error.error || error.message || 'Failed to submit application. Please try again.';
                showStatus(statusEl, 'error', message);
            }
        } catch (error) {
            console.error('Submission error:', error);
            showStatus(statusEl, 'error',
                'Network error. Please check your connection and try again.');
        } finally {
            submitBtn.disabled = false;
            submitBtn.textContent = 'Submit application';
        }
    }

    /**
     * Build FormData from the form, properly formatted for Recruitee API
     */
    function buildFormData(form) {
        const formData = new FormData();

        // Basic candidate fields
        const name = form.querySelector('#name')?.value;
        const email = form.querySelector('#email')?.value;
        const phone = form.querySelector('#phone')?.value;
        const coverLetter = form.querySelector('#cover_letter')?.value;
        const cvInput = form.querySelector('#cv');

        if (name) formData.append('candidate[name]', name);
        if (email) formData.append('candidate[email]', email);
        if (phone) formData.append('candidate[phone]', phone);
        if (coverLetter) formData.append('candidate[cover_letter]', coverLetter);

        // Handle CV file upload
        if (cvInput && cvInput.files && cvInput.files[0]) {
            formData.append('candidate[cv]', cvInput.files[0]);
        }

        // Handle open questions
        const questionInputs = form.querySelectorAll('[data-question-id]');
        questionInputs.forEach(input => {
            const questionId = input.dataset.questionId;

            if (input.type === 'checkbox') {
                // Handle multi-select checkboxes
                const checkboxGroup = input.closest('.checkbox-group');
                if (checkboxGroup && !checkboxGroup.dataset.processed) {
                    checkboxGroup.dataset.processed = 'true';
                    const checked = checkboxGroup.querySelectorAll('input:checked');
                    checked.forEach((checkbox, index) => {
                        formData.append(`candidate[open_question_answers_attributes][${questionId}][open_question_id]`, questionId);
                        formData.append(`candidate[open_question_answers_attributes][${questionId}][content][]`, checkbox.value);
                    });
                }
            } else if (input.value) {
                formData.append(`candidate[open_question_answers_attributes][${questionId}][open_question_id]`, questionId);
                formData.append(`candidate[open_question_answers_attributes][${questionId}][content]`, input.value);
            }
        });

        // Clean up processed flags
        form.querySelectorAll('.checkbox-group[data-processed]').forEach(group => {
            delete group.dataset.processed;
        });

        return formData;
    }

    /**
     * Submit application to Recruitee API
     */
    async function submitApplication(offerSlug, formData) {
        const url = `${RECRUITEE_API}/${offerSlug}/candidates`;

        return fetch(url, {
            method: 'POST',
            body: formData,
            // Don't set Content-Type header - browser will set it with boundary for multipart
        });
    }

    /**
     * Show status message
     */
    function showStatus(element, type, message) {
        if (!element) return;

        element.className = 'form-status ' + type;
        element.textContent = message;

        // Scroll status into view if not visible
        if (type === 'success' || type === 'error') {
            element.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
        }
    }

    // Initialize when DOM is ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
