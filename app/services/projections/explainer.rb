# app/services/projections/explainer.rb
module Projections
  class Explainer
    attr_reader :steps

    def initialize
      @steps = []
    end

    def add(step:, detail: nil, deltas: {}, data: {})
      @steps << {
        step: step,
        detail: detail,
        deltas: (deltas || {}).compact,
        data: (data || {}).compact
      }.compact
    end
  end
end
