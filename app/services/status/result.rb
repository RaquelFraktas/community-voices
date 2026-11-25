module Status
  # The outcome of one check: what was checked, whether it passed, what was found, and how to fix it if not.
  Result = Data.define(:name, :ok, :detail, :fix) do
    def self.passed(name, detail)
      new(name: name, ok: true, detail: detail, fix: nil)
    end

    def self.failed(name, detail, fix:)
      new(name: name, ok: false, detail: detail, fix: fix)
    end

    def ok?
      ok
    end
  end
end
