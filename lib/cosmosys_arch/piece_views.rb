require 'base64'

module CosmosysArch
  class PieceViews
    CAMERA_KEYS = %w[version projection position target up near far zoom fov frustum_height aspect material lighting background wireframe hidden section].freeze
    attr_reader :attachment, :prefix, :signature

    def initialize(attachment, prefix, configuration)
      @attachment, @prefix = attachment, prefix
      canonical = configuration.merge('controls' => Array(configuration['controls']).sort_by { |control| control['key'] })
      @signature = Digest::SHA256.hexdigest(JSON.generate(canonical))
    end

    def all
      PieceSavedView.where(attachment_id: attachment.id).where(name: all_names).preload(:image).order(:name)
    end

    def all_names
      # No SQL fragments or LIKE escaping: scope the small saved-view catalog
      # through Ruby and then use ActiveRecord's normal equality predicate.
      attachment.cad_preview_views.pluck(:name).select { |name| name == prefix || name.start_with?("#{prefix}--") }
    end

    def name_for(name)
      value = name.to_s.presence || 'default'
      raise ArgumentError, 'Invalid view name' unless CadPreviewView::NAME_FORMAT.match?(value)
      name = value == 'default' ? prefix : "#{prefix}--#{value}"
      raise ArgumentError, 'View name too long' if name.length > 64
      name
    end

    def find(name = 'default')
      PieceSavedView.find_by(attachment_id: attachment.id, name: name_for(name))
    end

    def current?(view)
      view && !view.stale? && view.state['architecture_signature'] == signature && view.image && File.file?(view.image.diskfile)
    end

    def save!(name, user:, attributes:)
      encoded = attributes.fetch('image').to_s
      raise ArgumentError, 'Image too large' if encoded.bytesize > 7.megabytes
      image = Base64.strict_decode64(encoded)
      state = attributes.fetch('state')
      raise ArgumentError, 'Invalid camera' unless state.is_a?(Hash)
      raise RedmineCadPreview::Views::Conflict unless attributes['signature'] == signature
      attachment.with_lock do
        view = find(name)
        raise RedmineCadPreview::Views::Conflict unless attributes['revision'].presence&.to_s == view&.revision&.to_s
        view ||= PieceSavedView.new(attachment: attachment, name: name_for(name))
        view.assign_attributes(user: user, state: state.slice(*CAMERA_KEYS).merge('architecture_signature' => signature), is_default: false)
        view.image_data = image
        view.save!
        view
      end
    end
  end
end
