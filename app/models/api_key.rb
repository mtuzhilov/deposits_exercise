# A credential for one API client. The plaintext token is returned exactly
# once, by ApiKey.issue!, and only its SHA-256 digest is stored. Tokens carry
# 256 bits of entropy, so a fast hash is sufficient (no bcrypt needed) and
# lets authentication be a single indexed lookup.
class ApiKey < ApplicationRecord
  TOKEN_PREFIX = "dpx_".freeze
  DISPLAY_PREFIX_LENGTH = 12
  LAST_USED_THROTTLE = 1.minute

  ROLES = %w[viewer operator admin].freeze

  PERMISSIONS = {
    "viewer" => %i[read_tradelines read_deposits],
    "operator" => %i[read_tradelines read_deposits create_deposit],
    "admin" => %i[read_tradelines read_deposits create_deposit create_tradeline read_audit_events]
  }.freeze

  has_many :audit_events, dependent: :restrict_with_error

  validates :name, presence: true, length: { maximum: 255 }
  validates :role, inclusion: { in: ROLES }
  validates :token_digest, :token_prefix, presence: true, uniqueness: true

  scope :active, -> { where(revoked_at: nil).where("expires_at IS NULL OR expires_at > ?", Time.current) }

  # Creates a key and returns [api_key, plaintext_token].
  def self.issue!(name:, role:, expires_at: nil)
    token = "#{TOKEN_PREFIX}#{SecureRandom.urlsafe_base64(32)}"
    key = create!(name: name, role: role.to_s, expires_at: expires_at,
                  token_digest: digest(token), token_prefix: token.first(DISPLAY_PREFIX_LENGTH))
    [key, token]
  end

  def self.authenticate(token)
    return if token.blank? || !token.start_with?(TOKEN_PREFIX)

    active.find_by(token_digest: digest(token))
  end

  def self.digest(token)
    OpenSSL::Digest::SHA256.hexdigest(token)
  end

  def can?(permission)
    PERMISSIONS.fetch(role, []).include?(permission)
  end

  def active?
    revoked_at.nil? && (expires_at.nil? || expires_at.future?)
  end

  def revoke!
    update!(revoked_at: Time.current) unless revoked_at
  end

  # Avoids a database write on every request.
  def touch_last_used!
    return if last_used_at && last_used_at > LAST_USED_THROTTLE.ago

    update_column(:last_used_at, Time.current)
  end

  def status
    return "revoked" if revoked_at
    return "expired" if expires_at&.past?

    "active"
  end
end
