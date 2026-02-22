import { X } from 'lucide-react';

export default function Modal({ isOpen, onClose, title, children, footer, size = 'md' }) {
    if (!isOpen) return null;

    const sizeClass = size === 'lg' ? 'max-width: 780px' : size === 'sm' ? 'max-width: 400px' : '';

    return (
        <div className="modal-overlay" onClick={onClose}>
            <div className="modal" style={sizeClass ? { maxWidth: size === 'lg' ? '780px' : '400px' } : {}} onClick={e => e.stopPropagation()}>
                <div className="modal-header">
                    <span className="modal-title">{title}</span>
                    <button className="btn-icon" onClick={onClose}>
                        <X size={16} />
                    </button>
                </div>
                <div className="modal-body">
                    {children}
                </div>
                {footer && (
                    <div className="modal-footer">
                        {footer}
                    </div>
                )}
            </div>
        </div>
    );
}
