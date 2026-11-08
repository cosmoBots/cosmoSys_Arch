module CosmosysArch
  # Reuse upstream camera/PNG storage without making a piece camera the
  # default camera of the complete CAD attachment. No new table is required.
  class PieceSavedView < ::CadPreviewView
    validate do
      data = state.is_a?(Hash) ? state : {}
      vectors = %w[position target up].map { |key| data[key] }
      numbers = %w[near far zoom].map { |key| data[key] }
      valid = vectors.all? { |vector| vector.is_a?(Array) && vector.size == 3 && vector.all? { |n| n.is_a?(Numeric) && n.finite? } } &&
        numbers.all? { |n| n.is_a?(Numeric) && n.finite? && n.positive? } &&
        data['far'] > data['near'] && %w[perspective orthographic].include?(data['projection'])
      errors.add(:state, :invalid) unless valid
    end

    private

    def set_default
      self.is_default = false
    end
  end
end
